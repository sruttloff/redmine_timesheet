# Run with: bundle exec rails runner plugins/redmine_timesheet/test/compatibility_smoke.rb
# All temporary records and settings are rolled back.
require 'securerandom'
require 'nokogiri'
require 'csv'
STDOUT.sync = true
raise 'Use development or test only' unless Rails.env.development? || Rails.env.test?
ActionMailer::Base.perform_deliveries = false
checks = 0
check = lambda do |condition, message|
  raise "FAIL: #{message}" unless condition
  checks += 1
  puts "PASS: #{message}"
end

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(4)
  password = SecureRandom.base64(24)
  create_user = lambda do |label, admin = false|
    user = User.new(login: "ts-#{label}-#{suffix}", firstname: label, lastname: 'Timesheet',
                    mail: "#{label}-#{suffix}@example.invalid", language: 'en', admin: admin)
    user.password = user.password_confirmation = password
    user.save!
    user
  end
  admin = create_user.call('Admin', true)
  owner = create_user.call('Owner')
  other = create_user.call('Other')
  User.current = admin
  role = Role.create!(name: "Timesheet own #{suffix}", permissions: [:view_time_entries, :log_time, :view_issues], time_entries_visibility: 'own')
  manager_role = Role.create!(name: "Timesheet manager #{suffix}", permissions: [:see_all_timesheets, :view_issues], time_entries_visibility: 'own')
  projects = 2.times.map do |index|
    project = Project.create!(name: "Timesheet #{index} #{suffix}", identifier: "timesheet-#{index}-#{suffix}", is_public: false)
    project.enabled_module_names = %w[time_tracking issue_tracking timesheet]
    project.trackers = [Tracker.first!]
    project
  end
  project, foreign = projects
  membership = Member.create!(project: project, user: owner, roles: [role])
  Member.create!(project: project, user: other, roles: [role])
  field = ProjectCustomField.create!(name: "Timesheet rate #{suffix}", field_format: 'float', is_for_all: true)
  project.reload
  project.custom_field_values = {field.id.to_s => '120.50'}
  project.save!
  settings = Redmine::Plugin.find(:redmine_timesheet).settings[:default].merge('invoice_rate_field_id' => field.id.to_s)
  Setting.plugin_redmine_timesheet = settings
  activity = TimeEntryActivity.active.where(parent_id: nil).first!
  alternative = TimeEntryActivity.create!(name: "Timesheet alternative #{suffix}", active: true)
  issue = Issue.create!(project: project, tracker: Tracker.first!, subject: "Visible <issue> #{suffix}", author: owner)
  hidden = Issue.create!(project: project, tracker: Tracker.first!, subject: "SECRET-#{suffix}", author: admin, is_private: true)
  create_entry = lambda do |user, target, hours, ticket = nil, selected_activity = activity|
    TimeEntry.create!(project: target, user: user, author: admin, issue: ticket, activity: selected_activity,
                      spent_on: User.current.today, hours: hours, comments: "Entry #{user.firstname} #{hours} <script>unsafe</script>")
  end
  own_entry = create_entry.call(owner, project, 1.234, issue)
  other_entry = create_entry.call(other, project, 2.345, nil)
  hidden_entry = create_entry.call(other, project, 0.5, hidden)
  alternate_entry = create_entry.call(owner, project, 0.25, nil, alternative)
  foreign_entry = create_entry.call(admin, foreign, 9)
  group = Group.create!(lastname: "Timesheet group #{suffix}")
  group.users << owner
  overlapping = Group.create!(lastname: "Timesheet overlapping #{suffix}")
  overlapping.users << owner

  login = lambda do |user|
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host! 'localhost'
    session.get '/login'
    token = Nokogiri::HTML(session.response.body).at_css('input[name="authenticity_token"]')&.[]('value')
    session.post '/login', params: {username: user.login, password: password, authenticity_token: token}
    check.call(session.response.redirect?, "login #{user.firstname}")
    session
  end
  session = login.call(owner)
  base = {period_type: '1', period: 'all', projects: [project.id.to_s], users: [owner.id.to_s, other.id.to_s], activities: [activity.id.to_s, alternative.id.to_s]}
  report = lambda do |filters = {}, format = nil, status = 200|
    session.get '/timesheet/report', params: {timesheet: base.merge(filters), format: format}
    check.call(session.response.status == status, "report #{filters[:sort]} #{format || 'html'} status #{status} (got #{session.response.status})#{session.response.status == status ? '' : session.response.body[0, 500]}")
    session.response
  end
  %w[project user issue group date].each do |sort|
    response = report.call({sort: sort})
    doc = Nokogiri::HTML(response.body)
    check.call(doc.css('tr.time_entry').map { |row| row['data-id'].to_i }.uniq.sort == [own_entry.id, alternate_entry.id].sort, "#{sort} only own permitted entries")
    check.call(!response.body.include?('<script>unsafe</script>') && response.body.include?('&lt;script&gt;unsafe'), "#{sort} escapes comments")
    response = report.call({sort: sort}, 'csv')
    rows = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true)
    check.call(rows.map { |row| row[0].to_i }.sort == [own_entry.id, alternate_entry.id].sort, "#{sort} CSV includes each entry once")
    check.call(rows.all? { |row| row['Hours'].match?(/\A\d+(\.\d+)?\z/) }, "#{sort} CSV hours are decimal numbers")
    response = report.call({sort: sort}, 'iif')
    check.call(response.body.scan(/^SPL\t/).length == 2, "#{sort} IIF includes each entry once")
    check.call(response.body.include?('ENDTRNS'), "#{sort} IIF completes transaction")
    iif_rows = CSV.parse(response.body, col_sep: "\t")
    balance = iif_rows.select { |row| %w[TRNS SPL].include?(row.first) }.sum { |row| BigDecimal(row[5]) }
    check.call(balance.zero?, "#{sort} IIF invoice balances exactly")
  end
  report.call({projects: [foreign.id.to_s]}, 'csv')
  check.call(!session.response.body.include?(foreign_entry.id.to_s + '",'), 'foreign project selection cannot expose data')
  report.call({users: [other.id.to_s]}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 1, 'forged other user is rejected in own-only role')
  report.call({projects: ['']}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 1, 'deselecting all projects returns no entries')
  report.call({projects: ['']})
  empty_link = Nokogiri::HTML(session.response.body).at_css('a[href*="report.csv"]')['href']
  session.get empty_link
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 1, 'empty project selection survives CSV URL')
  report.call({activities: ['']}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 1, 'deselecting all activities returns no entries')
  report.call({activities: [alternative.id.to_s]}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF"))[1][0].to_i == alternate_entry.id, 'activity filter applies')
  report.call({period_type: '0', date_from: 'bad-date'}, nil, 422)
  report.call({period_type: '0', date_from: '2026-10-16', date_to: '2026-10-01'}, nil, 422)
  %w[today yesterday current_week last_week 7_days current_month last_month 30_days current_year all].each do |period|
    report.call({period: period})
  end
  session.get '/timesheet/context_menu', params: {ids: [other_entry.id]}
  check.call(session.response.status == 404, 'context menu hides other users entries')
  session.get '/timesheet/context_menu', params: {ids: [foreign_entry.id]}
  check.call(session.response.status == 404, 'context menu hides foreign projects')
  session.get '/timesheet/context_menu', params: {ids: [own_entry.id]}
  check.call(session.response.status == 200 && session.response.body.include?('Edit'), 'context menu renders core edit actions')
  report.call({sort: 'date', groups: [group.id.to_s]})
  session.get '/timesheet/index'
  doc = Nokogiri::HTML(session.response.body)
  check.call(doc.at_css('#timesheet_sort option[selected]')['value'] == 'date', 'session remembers grouping')
  check.call(doc.at_css('#timesheet_period_type_1')['checked'], 'session remembers all-time period type')
  token = doc.at_css('meta[name="csrf-token"]')&.[]('content')
  session.delete '/timesheet/reset', params: {authenticity_token: token}
  check.call(session.response.redirect?, 'reset uses DELETE and redirects')
  session.get '/timesheet/index'
  check.call(Nokogiri::HTML(session.response.body).at_css('#timesheet_sort option[selected]')['value'] == 'project', 'reset clears saved filters')
  session.get '/timesheet/report'
  check.call(session.response.redirect?, 'missing filter redirects')
  session.get '/timesheet/report', params: {timesheet: base}, headers: {'X-Requested-With' => 'XMLHttpRequest'}
  check.call(session.response.status == 200, 'XHR report renders existing template')

  membership.roles = [manager_role]
  User.current = nil
  session = login.call(owner)
  report.call({sort: 'issue'})
  check.call(session.response.body.include?('Without a visible issue') && !session.response.body.include?(hidden.subject), 'manager sees issue-less entries without private issue metadata')
  report.call({}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 5, 'special permission alone can report project time')
  check.call(!session.response.body.include?(hidden.subject), 'CSV hides private issue metadata')
  report.call({}, 'iif')
  check.call(!session.response.body.include?(hidden.subject), 'IIF hides private issue metadata')
  report.call({groups: [group.id.to_s]}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 3, 'group filter intersects selected users')
  report.call({sort: 'group'})
  check.call(session.response.body.include?('Spent time (4.33'), 'overlapping groups do not inflate grand total')
  report.call({sort: 'group'}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 5, 'overlapping group export is deduplicated')
  Setting.plugin_redmine_timesheet = settings.merge('invoice_rate_field_id' => '')
  report.call({}, 'iif', 422)
  Setting.plugin_redmine_timesheet = settings
  field.update!(visible: false)
  report.call({}, 'iif', 422)
  check.call(session.response.body.include?('not visible to you'), 'IIF does not expose hidden hourly-rate fields')
  field.update!(visible: true)
  project.custom_field_values = {field.id.to_s => ''}
  project.save!
  report.call({}, 'iif', 422)
  project.custom_field_values = {field.id.to_s => '120.50'}
  project.save!

  session = login.call(admin)
  %w[en de].each do |language|
    admin.reload.update!(language: language)
    session = login.call(admin)
    session.get '/settings/plugin/redmine_timesheet'
    check.call(session.response.status == 200 && !session.response.body.include?('translation missing'), "#{language} settings render (#{session.response.status}, #{session.response.location}) #{session.response.body.scan(/translation missing[^<]*/i).inspect}")
    report.call({sort: 'group'})
    check.call(!session.response.body.include?('translation missing'), "#{language} report labels translate")
  end
  project.enabled_module_names = %w[time_tracking issue_tracking]
  report.call({}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 5, 'administrator sees all project time without Timesheet module')
  project.enabled_module_names = %w[time_tracking issue_tracking timesheet]
  project.update_column(:status, Project::STATUS_ARCHIVED)
  session.get '/timesheet/index'
  check.call(!Nokogiri::HTML(session.response.body).css('#timesheet_projects_ option').map { |option| option['value'] }.include?(project.id.to_s), 'active setting hides archived projects')
  Setting.plugin_redmine_timesheet = settings.merge('project_status' => 'all')
  report.call({}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 5, 'all-project setting reads archived time as admin')
  session = login.call(owner)
  report.call({}, 'csv')
  check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 5, 'archived project preserves member permission')
  stranger = create_user.call('Stranger')
  session = login.call(stranger)
  # The host installation may grant time tracking in public projects to non-members.
  status = Timesheet.allowed_projects(stranger).any? ? 200 : 403
  session.get '/timesheet/report', params: {timesheet: base, format: 'csv'}
  check.call(session.response.status == status, 'unrelated user cannot report private fixture project')
  if status == 200
    check.call(CSV.parse(session.response.body.delete_prefix("\uFEFF")).length == 1, 'public-project access does not expose private fixture entries')
  end
  session.get '/timesheet/context_menu', params: {ids: [own_entry.id]}
  check.call([403, 404].include?(session.response.status), 'unauthorized context request is denied')
  raise ActiveRecord::Rollback
end
User.current = nil
Setting.clear_cache
puts "PASS: #{checks} checks; temporary data rolled back"
