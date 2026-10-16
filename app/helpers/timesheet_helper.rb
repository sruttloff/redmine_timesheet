module TimesheetHelper
  include ProjectsHelper

  def add_day_total?(entries, index)
    index == entries.length - 1 || entries[index + 1].spent_on != entries[index].spent_on
  end

  def calculate_day_total(entries, index)
    date = entries[index].spent_on
    number_with_precision(entries.take(index + 1).reverse.take_while { |entry| entry.spent_on == date }.sum(&:hours), precision: @precision)
  end

  def add_week_number?(entries, index)
    index.zero? || entries[index - 1].spent_on.cwyear != entries[index].spent_on.cwyear ||
      entries[index - 1].spent_on.cweek != entries[index].spent_on.cweek
  end

  def time_entry_title(entry)
    "#{l(:timesheet_label_week_number)} #{entry.spent_on.cweek}"
  end

  def showing_users(users)
    l(:timesheet_showing_users) + users.map(&:name).join(', ')
  end

  def permalink_to_timesheet(timesheet)
    link_to l(:timesheet_permalink), controller: 'timesheet', action: 'report', timesheet: timesheet.to_param
  end

  def link_to_csv_export(timesheet)
    link_to 'CSV', {controller: 'timesheet', action: 'report', format: 'csv', timesheet: timesheet.to_param}, class: 'icon icon-timesheet'
  end

  def link_to_iif_export(timesheet)
    link_to 'QuickBooks (IIF)', {controller: 'timesheet', action: 'report', format: 'iif', timesheet: timesheet.to_param}, class: 'icon icon-timesheet'
  end

  def toggle_issue_arrows(id)
    link_to sprite_icon('angle-right'), '#', class: 'timesheet-toggle', data: {timesheet_toggle: id},
            title: l(:button_expand_all), 'aria-label' => l(:button_expand_all), 'aria-expanded' => 'false'
  end

  def project_options(timesheet)
    project_tree_options_for_select(timesheet.allowed_projects, selected: timesheet.projects)
  end

  def activity_options(timesheet, activities)
    options_from_collection_for_select(activities, :id, :name, timesheet.activities)
  end

  def group_options(timesheet)
    options_from_collection_for_select(Group.givable.sorted, :id, :name, timesheet.groups)
  end

  def user_options(timesheet)
    options_from_collection_for_select(Timesheet.viewable_users, :id, :name, timesheet.users)
  end

  def options_for_period_select(value)
    options_for_select([[l(:label_last_week), 'last_week'], [l(:label_this_week), 'current_week'],
                        [l(:timesheet_all_time), 'all'], [l(:label_today), 'today'], [l(:label_yesterday), 'yesterday'],
                        [l(:label_last_n_days, 7), '7_days'], [l(:label_this_month), 'current_month'],
                        [l(:label_last_month), 'last_month'], [l(:label_last_n_days, 30), '30_days'],
                        [l(:label_this_year), 'current_year']], value)
  end
end
