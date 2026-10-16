# Redmine Timesheet for Redmine 6.1

Timesheet lists and filters time entries across Redmine projects. Group reports by project, user, issue, group, or date, print timesheets, and export the selected entries.

This fork is maintained for Redmine 6.1 by **[SaaS-Secure.com, S. Ruttloff](https://www.saas-secure.com/)**. It is based on [Intera's Redmine Timesheet](https://github.com/Intera/redmine_timesheet), originally developed by Eric Davis, with contributions from Arkhitech and the community.

**Version: 1.0.0.** Validated with Redmine **6.1.2-stable**, Rails **7.2.3**, Ruby **3.3.7**, and MySQL **8.4.11**. See the [validation report](doc/REDMINE_6_1_VALIDATION.md) for coverage and limitations and the [changelog](CHANGELOG.md) for changes. Other Redmine releases and database adapters have not been confirmed.

## Features

- Filter by date range or a predefined period, projects, activities, users, and groups.
- Group by project, user, issue, group, or date, with group totals and a grand total.
- Include time entries without an issue; hide issue details that the current user cannot view.
- Expand issue and date groups, select entries, and use Redmine's context menu for editing or deleting permitted entries.
- Remember filters in the session, reset them, or share a permalink.
- Export UTF-8 CSV with a BOM for spreadsheet applications, for all five groupings.
- Export QuickBooks desktop invoice data as IIF using a configurable project hourly rate.
- Print reports with calendar week numbers and daily totals, including collapsed sections.
- Configure list size, decimal precision, active/all projects, and active/all users.
- English and German interface labels, with existing community translations retained for other languages.
- Extension hooks for forms, reports, query conditions, and CSV output.

## Requirements

- Redmine 6.1 and the Ruby/Rails versions supported by that Redmine release.
- Standard Redmine time tracking; no additional plugin gems and no plugin database migrations.
- A backup of the application and database before an upgrade.

## Installation

The directory must be named exactly `redmine_timesheet`:

```sh
cd /path/to/redmine/plugins
git clone --branch v1.0.0 https://github.com/sruttloff/redmine_timesheet.git redmine_timesheet
cd /path/to/redmine
bundle install
```

If your deployment uses precompiled assets, rebuild them:

```sh
bundle exec rake assets:precompile RAILS_ENV=production
```

Restart the Redmine application server using your deployment's Puma, Passenger, systemd, or Docker procedure. This plugin does not need `redmine:plugins:migrate`.

For an upgrade, back up first, fetch and check out the desired published tag, run `bundle install`, rebuild assets if applicable, and restart. The obsolete `webrat` and `riif` dependencies are no longer needed by this plugin.

## Setup and permissions

1. Enable **Time tracking** in each project to be reported.
2. Grant **View spent time** (`view_time_entries`) to users who should report their own time.
3. To report other users' time, also enable **Timesheet** in the relevant project and grant **View other users' timesheets in this project** (`see_all_timesheets`). This permission is sufficient for reporting that project's time even without the standard view permission. Grant standard edit permissions separately if required.
4. Open **Timesheet** in the main navigation. The link appears when at least one project is accessible to the user.
5. Under **Administration → Plugins → Timesheet → Configure**, adjust list size, decimal places, project status, user status, and the optional IIF rate field.

Ordinary users see their own entries in authorized projects. Administrators see all entries. The special Timesheet permission grants access to other users' entries **only in projects where that permission is held**; it does not grant access to unrelated private projects. This plugin deliberately keeps its own-only behavior for ordinary users even if their standard Redmine role can view all spent time.

The **active projects** setting includes active projects only. **All projects** also includes closed and archived projects, using the retained membership/role permissions for archived projects. Reporting archived entries is read-only; Redmine's standard edit/delete permissions still apply. Private or otherwise inaccessible issue subjects, versions, and links are omitted from reports and exports, even when the associated time entry is reportable.

The **user status** setting controls the user selection list, including historical time from locked users when **All users** is selected.

## Usage

1. Select a predefined period or enter an inclusive `YYYY-MM-DD` date range. The date fields and period selector automatically activate their corresponding radio button. **Last 7/30 days** includes today and the preceding 6/29 days.
2. Select projects, activities, and users. Click a list heading to select or deselect all its items. An empty selection returns no entries.
3. Optionally select groups to restrict the chosen users to group members. No selected groups means no group restriction. Group filters intersect with the user selection.
4. Choose a grouping and click **Apply**. Issue/date sections can be expanded using their arrow.
5. Use **CSV**, **QuickBooks (IIF)**, or **Permalink** above the report. Exports include each matching entry once, independent of collapsed rows or overlapping user groups.
6. Use row actions or right-click a row for Redmine's context menu. Editing and deletion use Redmine's own forms, permissions, and confirmation dialogs.
7. Use your browser's print command for the print layout. It includes expanded data, week numbers, and day totals.
8. **Reset** clears saved filters. Large selections are not stored in the session to avoid oversized cookies; they remain usable in the current request and permalink.

A user in several groups can appear under several group headings; the grand total and exports count that user's entries once. Users without a group appear under **Without group**.

### QuickBooks IIF

Create a numeric **Project** custom field (integer or float), make it available to the relevant projects, and fill in each project's hourly rate. Select that field in the Timesheet plugin settings. The exporter respects the field's visibility permissions. Hidden, missing, invalid, or negative rates produce a readable validation message instead of an incomplete export. Zero is a valid rate.

The exporter writes one balanced invoice transaction per project, using the project name as the customer and the accounts `Accounts Receivable` and `Service Income`. Tabs, newlines, and quotation marks in text fields are normalized. Invoice amounts are rounded to two decimal places per line. Entries without an issue and all-time reports are supported.

The generated IIF structure and amounts are tested. Import into a particular QuickBooks desktop version has **not** been tested; account/customer names, encoding, taxes, currencies, and invoice numbering must be reviewed for the target accounting workflow. This is a basic invoice interchange export, not a full accounting integration.

## Changes for Redmine 6.1

- Removed obsolete Rails scopes, model patches, Prototype JavaScript, image filenames, and the `link_to_function` helper.
- Removed the old Rails Engines/Webrat test dependency and `riif` template renderer.
- Updated routing, context menus, SVG icons, delete confirmation handling, and strong parameters.
- Unified project and user authorization for every grouping, export, and context-menu request.
- Fixed issue-less entries, empty selections and permalinks, duplicate project/user names, group filtering, and group/date CSV exports.
- Corrected period selection, session persistence, week boundaries, rounding of totals, and print expansion.
- Added a configurable IIF hourly rate and validation, replacing the hard-coded custom field ID.

## Validation and development

Run from a development or test Redmine installation with its normal database migrations applied, at least one tracker, and at least one time-entry activity:

```sh
bundle exec rake zeitwerk:check
bundle exec rails runner plugins/redmine_timesheet/test/compatibility_smoke.rb
bundle exec rails runner plugins/redmine_timesheet/test/reload_smoke.rb
```

The compatibility script creates temporary users, projects, groups, issues, time entries, and rate settings inside a transaction and rolls everything back. It checks actual authenticated Rails requests, all groupings and exports, visibility boundaries, periods, invalid dates, saved filters, reset, settings localization, archived projects, and private issues.

The reload test isolates Timesheet reinitialization because other installed plugins may have their own reload issues. The legacy Rails 2/3 Webrat tests have been replaced by these executable regression checks. Browser checks and practical limits are documented in the [validation report](doc/REDMINE_6_1_VALIDATION.md).

## More plugins from SaaS-Secure.com

- **[Redmine UX Toolkit](https://www.saas-secure.com/online-services/redmine-ux-toolkit.html)** – Interface improvements, dashboards, checklists, templates, reminders, and administration tools.
- **[SCM Creator for Redmine](https://www.saas-secure.com/online-services/redmine-scm.html)** – Repository management for Git, Subversion, Mercurial, Bazaar, and GitHub.

These plugins are optional and are not required by Timesheet. For hosting and other services, visit **[www.saas-secure.com](https://www.saas-secure.com/)**.

## Support and credits

Report issues through **[GitHub Issues](https://github.com/sruttloff/redmine_timesheet/issues)**. Include the Redmine, Ruby, Rails, and database versions, reproduction steps, and relevant errors without credentials or private time-entry data.

- Original development: Eric Davis / Little Stream Software.
- Upstream maintenance: [Intera GmbH](https://github.com/Intera/redmine_timesheet).
- Contributions: Arkhitech and the contributors listed in [credits.txt](credits.txt).
- Redmine 6.1 adaptation and maintenance of this fork: **[SaaS-Secure.com, S. Ruttloff](https://www.saas-secure.com/)**.

## License

**GNU GPL version 2 or later**, as stated in the original [copyright notice](copyright.txt). The original notices and [GPL license text](gpl.txt) are preserved.
