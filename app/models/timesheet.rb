require 'csv'
require 'bigdecimal'

class Timesheet
  class InvalidFilter < StandardError; end

  attr_accessor :date_from, :date_to, :projects, :activities, :users, :groups,
                :allowed_projects, :period_type, :time_entries, :potential_time_entry_ids
  attr_reader :sort, :period, :selected_project_ids, :entries

  ValidSortOptions = {user: :label_user, project: :label_project, issue: :label_issue,
                      group: :label_group, date: :label_date}.freeze
  ValidPeriodType = {free_period: 0, default: 1}.freeze
  PERIODS = %w[today yesterday current_week last_week 7_days current_month last_month 30_days current_year all].freeze

  def initialize(options = {})
    options = options.to_h.with_indifferent_access
    @projects = []
    @allowed_projects = options[:allowed_projects] || []
    @selected_project_ids = ids(options[:projects]) if options.key?(:projects)
    @time_entries = {}
    @entries = []
    @potential_time_entry_ids = ids(options[:potential_time_entry_ids])
    @activities = if options.key?(:activities)
                    selected = ids(options[:activities])
                    TimeEntryActivity.where(id: selected).or(TimeEntryActivity.where(parent_id: selected)).pluck(:id)
                  else
                    TimeEntryActivity.pluck(:id)
                  end
    @users = options.key?(:users) ? ids(options[:users]) : self.class.viewable_users.map(&:id)
    @groups = ids(options[:groups])
    @sort = ValidSortOptions.key?(options[:sort].to_s.to_sym) ? options[:sort].to_sym : :project
    @period_type = options[:period_type].to_s == '1' ? 1 : 0
    @date_from = options[:date_from].presence || User.current.today.to_s
    @date_to = options[:date_to].presence || User.current.today.to_s
    self.period = options[:period].presence || 'today'
    validate_dates
  end

  def self.roles_for(user, project)
    return user.roles_for_project(project) unless project.archived?

    membership = Member.includes(:roles).find_by(project_id: project.id, user_id: user.id) if user.logged?
    membership ? membership.roles.to_a : (project.is_public? ? project.override_roles(user.builtin_role) : [])
  end

  # The special permission grants access to other users only in its own project.
  def self.permission?(permission, project, user = User.current)
    required_module = permission == :see_all_timesheets ? 'timesheet' : 'time_tracking'
    return false unless project.module_enabled?(required_module)
    return false if project.archived? && Setting.plugin_redmine_timesheet['project_status'] != 'all'
    return true if user.admin?

    roles_for(user, project).any? { |role| role.allowed_to?(permission) }
  end

  def self.allowed_projects(user = User.current)
    scope = Project.order(:name, :id)
    scope = scope.active unless Setting.plugin_redmine_timesheet['project_status'] == 'all'
    scope.includes(:enabled_modules).select do |project|
      project.module_enabled?('time_tracking') &&
        (permission?(:view_time_entries, project, user) || permission?(:see_all_timesheets, project, user))
    end
  end

  def self.see_others?(user = User.current)
    user.admin? || allowed_projects(user).any? { |project| permission?(:see_all_timesheets, project, user) }
  end

  def self.visible_entries(user = User.current)
    projects = allowed_projects(user)
    all_ids = if user.admin?
                projects.map(&:id)
              else
                projects.select { |project| permission?(:see_all_timesheets, project, user) }.map(&:id)
              end
    own_ids = projects.map(&:id) - all_ids
    TimeEntry.where(project_id: all_ids).or(TimeEntry.where(project_id: own_ids, user_id: user.id))
  end

  def self.viewable_users
    return [User.current] unless see_others?

    Setting.plugin_redmine_timesheet['user_status'] == 'all' ? User.sorted.to_a : User.active.sorted.to_a
  end

  def period=(value)
    @period = PERIODS.include?(value.to_s) ? value.to_s : 'today'
    return if period_type == ValidPeriodType[:free_period]

    today = User.current.today
    @date_from, @date_to = case @period
                         when 'today' then [today, today]
                         when 'yesterday' then [today - 1, today - 1]
                         when 'current_week' then [today.beginning_of_week, today.end_of_week]
                         when 'last_week' then [(today - 7).beginning_of_week, (today - 7).end_of_week]
                         when '7_days' then [today - 6, today]
                         when 'current_month' then [today.beginning_of_month, today.end_of_month]
                         when 'last_month' then [(today << 1).beginning_of_month, (today << 1).end_of_month]
                         when '30_days' then [today - 29, today]
                         when 'current_year' then [today.beginning_of_year, today.end_of_year]
                         when 'all' then [nil, nil]
                         end
  end

  def fetch_time_entries
    scope = self.class.visible_entries.where(project_id: projects.map(&:id), user_id: users, activity_id: activities)
    scope = scope.where(spent_on: date_from..date_to) if date_from && date_to
    scope = scope.where(id: potential_time_entry_ids) if potential_time_entry_ids.any?
    # Group and User share the users table (STI); avoid selecting the group side of a self-join.
    scope = scope.where(user_id: Group.givable.where(id: groups).includes(:users).flat_map { |group| group.users.map(&:id) }) if groups.any?
    # Preserve extension hooks without allowing them to remove the visibility scope.
    conditions = ["#{TimeEntry.table_name}.project_id IN (:projects)",
                  {from: date_from, to: date_to, projects: projects.map(&:id), users: users,
                   activities: activities, groups: groups, potential_time_entries: potential_time_entry_ids}]
    Redmine::Hook.call_hook(:plugin_timesheet_model_timesheet_conditions, timesheet: self, conditions: conditions)
    includes = [:activity, :user, :project, {issue: [:tracker, :assigned_to, :priority, :fixed_version]}]
    Redmine::Hook.call_hook(:plugin_timesheet_model_timesheet_includes, timesheet: self, includes: includes)
    @entries = scope.where(conditions).includes(includes).order(:spent_on, :id).to_a
    @time_entries = {}
    case sort
    when :issue
      entries.group_by(&:project).each do |project, logs|
        @time_entries[project] = {issues: logs.group_by { |entry| visible_issue(entry) }, users: logs.map(&:user).uniq}
      end
    when :group
      selected_groups = groups.any? ? Group.givable.where(id: groups) : Group.givable
      assigned = []
      selected_groups.sorted.includes(:users).each do |group|
        member_ids = group.users.map(&:id)
        logs = entries.select { |entry| member_ids.include?(entry.user_id) }
        next if logs.empty?

        assigned.concat(logs)
        @time_entries[group.name] = {logs: logs, users: logs.map(&:user).uniq}
      end
      ungrouped = entries - assigned
      @time_entries[I18n.t(:timesheet_without_group)] = {logs: ungrouped, users: ungrouped.map(&:user).uniq} if ungrouped.any?
    else
      entries.group_by do |entry|
        case sort
        when :user then entry.user
        when :date then entry.spent_on
        else entry.project
        end
      end.each do |key, logs|
        @time_entries[key] = {logs: logs, users: logs.map(&:user).uniq}
      end
    end
    time_entries
  end

  def visible_issue(entry)
    issue = entry.issue
    issue if issue && (User.current.admin? || issue.visible?)
  end

  def to_param
    # Empty arrays are otherwise omitted from URLs, turning an empty selection into the default selection.
    {projects: projects.empty? ? [''] : projects.map(&:id), date_from: date_from, date_to: date_to,
     period_type: period_type, period: period, activities: activities.empty? ? [''] : activities,
     users: users.empty? ? [''] : users, groups: groups, sort: sort}
  end

  def to_csv
    header = ['#', I18n.t(:label_date), I18n.t(:label_member), I18n.t(:label_activity), I18n.t(:label_project),
              I18n.t(:label_version), I18n.t(:label_issue), "#{I18n.t(:label_issue)} #{I18n.t(:field_subject)}",
              I18n.t(:field_comments), I18n.t(:field_hours)]
    Redmine::Hook.call_hook(:plugin_timesheet_model_timesheet_csv_header, timesheet: self, csv_data: header)
    "\uFEFF" + CSV.generate(force_quotes: true, encoding: 'UTF-8') do |csv|
      csv << header
      entries.each do |entry|
        issue = visible_issue(entry)
        row = [entry.id, entry.spent_on, entry.user.name, entry.activity.name, entry.project.name,
               issue&.fixed_version&.name, ("#{issue.tracker.name} ##{issue.id}" if issue), issue&.subject,
               entry.comments, entry.hours.to_f]
        Redmine::Hook.call_hook(:plugin_timesheet_model_timesheet_time_entry_to_csv, timesheet: self, time_entry: entry, csv_data: row)
        csv << row
      end
    end
  end

  # QuickBooks desktop invoice interchange; project custom fields supply hourly rates.
  def to_iif
    field_id = Setting.plugin_redmine_timesheet['invoice_rate_field_id'].to_i
    field = ProjectCustomField.find_by(id: field_id, field_format: ['float', 'int'])
    raise InvalidFilter, I18n.t(:timesheet_invoice_rate_required) unless field

    rates = entries.to_h do |entry|
      raise InvalidFilter, I18n.t(:timesheet_invoice_rate_hidden) unless field.visible_by?(entry.project)

      raw = entry.project.custom_field_value(field_id).to_s
      begin
        rate = BigDecimal(raw)
        raise ArgumentError if rate.negative? || !rate.finite?
      rescue ArgumentError
        raise InvalidFilter, I18n.t(:timesheet_invoice_rate_invalid, project: entry.project.name)
      end
      [entry.id, rate]
    end
    CSV.generate(col_sep: "\t", row_sep: "\r\n", encoding: 'UTF-8') do |csv|
      csv << ['!ACCNT', 'NAME', 'ACCNTTYPE']
      csv << ['ACCNT', 'Accounts Receivable', 'AR']
      csv << ['ACCNT', 'Service Income', 'INC']
      csv << ['!TRNS', 'TRNSTYPE', 'DATE', 'ACCNT', 'NAME', 'AMOUNT', 'DOCNUM', 'MEMO']
      csv << ['!SPL', 'TRNSTYPE', 'DATE', 'ACCNT', 'NAME', 'AMOUNT', 'QNTY', 'PRICE', 'MEMO']
      csv << ['!ENDTRNS']
      entries.group_by(&:project).each do |project, logs|
        total = logs.sum { |entry| (rates.fetch(entry.id) * BigDecimal(entry.hours.to_f.to_s)).round(2) }
        csv << ['TRNS', 'INVOICE', User.current.today.strftime('%m/%d/%Y'), 'Accounts Receivable', clean_iif(project.name),
                total.to_s('F'), "TS-#{project.id}-#{User.current.today.strftime('%Y%m%d')}", 'Redmine timesheet']
        logs.each do |entry|
          rate = rates.fetch(entry.id)
          issue = visible_issue(entry)
          memo = "#{entry.user.name} #{entry.spent_on} #{issue ? "##{issue.id} #{issue.subject}" : ''} #{entry.comments}"
          csv << ['SPL', 'INVOICE', entry.spent_on.strftime('%m/%d/%Y'), 'Service Income', clean_iif(project.name),
                  (-(rate * BigDecimal(entry.hours.to_f.to_s)).round(2)).to_s('F'), -entry.hours.to_f, rate.to_s('F'), clean_iif(memo)]
        end
        csv << ['ENDTRNS']
      end
    end
  end

  private

  def ids(value)
    Array(value).reject(&:blank?).map(&:to_i).select(&:positive?).uniq
  end

  def validate_dates
    return if period_type == 1 && period == 'all'

    @date_from = Date.iso8601(date_from.to_s)
    @date_to = Date.iso8601(date_to.to_s)
    raise ArgumentError if date_from > date_to
  rescue ArgumentError, TypeError
    raise InvalidFilter, I18n.t(:timesheet_invalid_dates)
  end

  def clean_iif(value)
    value.to_s.gsub(/[\t\r\n"]/, ' ')
  end
end
