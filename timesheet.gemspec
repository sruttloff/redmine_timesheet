Gem::Specification.new do |spec|
  spec.name = 'redmine_timesheet'
  spec.version = '1.0.0'
  spec.summary = 'Timesheet reports and exports for Redmine 6.1'
  spec.description = 'Filter time entries across projects, group reports, and export CSV or QuickBooks IIF.'
  spec.authors = ['Eric Davis', 'Intera GmbH', 'Arkhitech', 'SaaS-Secure.com, S. Ruttloff']
  spec.homepage = 'https://github.com/sruttloff/redmine_timesheet'
  spec.license = 'GPL-2.0-or-later'
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir['app/**/*', 'assets/**/*', 'config/**/*', 'test/**/*', 'doc/**/*'] +
               %w[init.rb Gemfile readme.md CHANGELOG.md copyright.txt credits.txt gpl.txt]
  spec.require_paths = []
end
