class TimesheetController < ApplicationController
  layout 'base'
  before_action :prepare_timesheet
  helper :issues, :timelog, :context_menus
  SessionKey = 'timesheet_filter'.freeze

  def index
    @timesheet = Timesheet.new(session[SessionKey] || {})
    assign_projects
    render :no_projects if @timesheet.allowed_projects.empty?
  rescue Timesheet::InvalidFilter => e
    session.delete(SessionKey)
    @timesheet = Timesheet.new
    assign_projects
    flash.now[:error] = e.message
  end

  def report
    return redirect_to(action: 'index') unless params[:timesheet]

    @timesheet = Timesheet.new(filter_params.to_h)
    assign_projects
    return render(:no_projects) if @timesheet.allowed_projects.empty?

    call_hook(:plugin_timesheet_controller_report_pre_fetch_time_entries, timesheet: @timesheet, params: params)
    @timesheet.fetch_time_entries
    save_filters
    @total = @timesheet.time_entries.transform_values do |entry|
      (entry[:logs] || entry[:issues].values.flatten).sum(&:hours)
    end
    # Groups may overlap; count each entry once in the grand total.
    @grand_total = @timesheet.entries.sum(&:hours)
    respond_to do |format|
      format.html { render :report, layout: !request.xhr? }
      format.csv { send_data @timesheet.to_csv, filename: 'timesheet.csv', type: 'text/csv; charset=utf-8' }
      format.iif { send_data @timesheet.to_iif, filename: 'timesheet.iif', type: 'application/octet-stream' }
    end
  rescue Timesheet::InvalidFilter => e
    render plain: e.message, status: :unprocessable_entity
  end

  def context_menu
    @time_entries = Timesheet.visible_entries.where(id: params[:ids]).to_a
    return render_404 if @time_entries.empty? || @time_entries.size != Array(params[:ids]).uniq.size

    @time_entry = @time_entries.first if @time_entries.one?
    @can = {edit: @time_entries.all? { |entry| entry.editable_by?(User.current) }}
    @can[:delete] = @can[:edit]
    @activities = @time_entries.map { |entry| entry.project.activities }.reduce(:&)
    @options_by_custom_field = {}
    @back = back_url
    render :context_menu, layout: false
  end

  def reset
    session.delete(SessionKey)
    redirect_to action: 'index'
  end

  private

  def prepare_timesheet
    @allowed_projects = Timesheet.allowed_projects
    return deny_access unless User.current.admin? || @allowed_projects.any?

    settings = Setting.plugin_redmine_timesheet
    @list_size = settings['list_size'].to_i.clamp(2, 30)
    @precision = settings['precision'].to_i.clamp(0, 10)
    @activities = TimeEntryActivity.where(parent_id: nil).sorted
  end

  def filter_params
    params.require(:timesheet).permit(:date_from, :date_to, :period, :period_type, :sort,
                                     projects: [], activities: [], users: [], groups: [])
  end

  def assign_projects
    @timesheet.allowed_projects = @allowed_projects
    selected = @timesheet.selected_project_ids
    @timesheet.projects = selected.nil? ? @allowed_projects : @allowed_projects.select { |project| selected.include?(project.id) }
  end

  def save_filters
    filters = @timesheet.to_param.transform_values do |value|
      value.is_a?(Array) ? value.map(&:to_s) : value.to_s
    end
    # Leave room for Redmine's other session data and encrypted cookie overhead.
    if filters.to_json.bytesize < 1500
      session[SessionKey] = filters
    else
      session.delete(SessionKey)
    end
  end
end
