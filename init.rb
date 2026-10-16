require "redmine"
Mime::Type.register 'application/x-iif', :iif unless Mime::Type.lookup_by_extension(:iif)

unless Redmine::Plugin.registered_plugins.keys.include?(:redmine_timesheet)
  Redmine::Plugin.register :redmine_timesheet do
    author "SaaS-Secure.com, S. Ruttloff"
    author_url "https://www.saas-secure.com/"
    description "This is a Timesheet plugin for Redmine to show timelogs for all projects"
    name "Redmine Timesheet Plugin"
    requires_redmine :version_or_higher => "6.1.0"
    url "https://github.com/sruttloff/redmine_timesheet"
    version "1.0.0"
    settings(:default => {
               "list_size" => "5",
               "precision" => "2",
               "project_status" => "active",
               "user_status" => "active",
               "invoice_rate_field_id" => ""
             }, :partial => "settings/timesheet_settings")
    project_module :timesheet do
	    permission :see_all_timesheets, {}, :read => true, :require => :loggedin
    end
    menu(:top_menu,
         :timesheet,
         {:controller => :timesheet, :action => :index},
         :caption => :timesheet_title,
         :if => Proc.new {
           Timesheet.allowed_projects.any?
         })
  end
end
