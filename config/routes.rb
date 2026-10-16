get 'timesheet/index', to: 'timesheet#index'
get 'timesheet/context_menu', to: 'timesheet#context_menu'
match 'timesheet/report', to: 'timesheet#report', via: [:get, :post]
delete 'timesheet/reset', to: 'timesheet#reset'
