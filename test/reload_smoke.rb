# Run with bundle exec rails runner plugins/redmine_timesheet/test/reload_smoke.rb
raise 'Use development or test only' unless Rails.env.development? || Rails.env.test?
STDOUT.sync = true
other_plugins = Redmine::Plugin.all.reject { |plugin| plugin.id == :redmine_timesheet }
# Only reinitialize Timesheet: unrelated installed plugins may not support repeated initialization.
Redmine::PluginLoader.singleton_class.prepend(Module.new do
  def directories
    super.select { |directory| File.basename(directory.to_s) == 'redmine_timesheet' }
  end
end)
3.times do |index|
  Rails.application.reloader.reload!
  # Core models may still receive another plugin's on-load patch. Keep its setting getters available
  # without running that plugin's initializer again in this isolated process.
  other_plugins.each { |plugin| Setting.define_plugin_setting(plugin) }
  User.current = User.where(admin: true).first!
  sheet = Timesheet.new(period_type: '1', period: 'all')
  sheet.projects = Timesheet.allowed_projects
  sheet.fetch_time_entries
  raise 'CSV unavailable after reload' unless sheet.to_csv.start_with?("\uFEFF")
  raise 'MIME registration lost' unless Mime::Type.lookup_by_extension(:iif)
  raise 'Plugin version mismatch' unless Redmine::Plugin.find(:redmine_timesheet).version == '1.0.0'
  puts "PASS: reload #{index + 1}: plugin, queries, CSV and IIF MIME registration"
end
User.current = nil
