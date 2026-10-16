# Redmine 6.1 validation – Timesheet 1.0.0

Date: 2026-10-16 (Europe/Berlin).

## Environment

- Redmine 6.1.2-stable, Rails 7.2.3, Ruby 3.3.7.
- MySQL 8.4.11, Linux Docker application container; sources on Windows.
- Local development instance at http://localhost:8080.
- Codex integrated browser, with both an administrator and a temporary ordinary user.
- Existing UX Toolkit, Contacts/Helpdesk, Redcase, Work Time, Knowledgebase, and other plugins remained installed.

## Automated checks

| Check | Result |
| --- | --- |
| `bundle check` | Dependencies satisfied without Webrat or riif |
| `bundle exec rake zeitwerk:check` | All is good |
| `bundle exec rake assets:precompile` | Completed; Timesheet JS/CSS/images generated |
| `bundle exec rails runner plugins/redmine_timesheet/test/compatibility_smoke.rb` | **124 checks passed**, temporary data rolled back |
| `bundle exec rails runner plugins/redmine_timesheet/test/reload_smoke.rb` | **3 isolated reload cycles passed** |
| Plugin gemspec | Loads with version 1.0.0 and GPL-2.0-or-later metadata |
| `git diff --check` | Passed |

The transactional regression suite covers authenticated requests for project, user, issue, group, and date grouping; HTML, CSV, and IIF for each grouping; issue-less entries; all preset periods; inclusive custom ranges; invalid/reversed dates; empty project/activity selections and export URLs; activity filtering; forged project/user IDs; private issue metadata; context-menu authorization; saved filters and DELETE reset; XHR rendering; group/user intersection; overlapping groups; decimal CSV hours; balanced IIF transactions; missing rate configuration and project rates; English/German labels and settings; active/archived projects; retained archived membership permissions; administrators without the Timesheet module; and unrelated users with access to public projects.

## Integrated browser checks

| Workflow | Observed result |
| --- | --- |
| Menu and filter form | Loads correctly after application restart, without missing translations |
| Project report | Selected test project contains 3 entries totaling 4.50 hours; the other test project is excluded |
| User grouping | Separate user headings and exact totals; configured three decimal places are applied |
| Issue grouping | Issue entries total 3.75 hours; the issue-less entry remains visible as a separate 0.75-hour group |
| Date grouping | Two date headings, 2.50 and 2.00 hours; expansion/collapse works |
| Group grouping | Test team report totals 4.50 hours; group and user filters intersect correctly |
| Select-all headings | User list toggles between selected and empty; empty selection reports no data |
| Row selection | Header checkbox selects/clears all three entry checkboxes |
| Context menu | Right-click loads Redmine edit/activity/delete actions for the selected row |
| Edit | Context-menu edit opens the core Redmine form; changing 0.75 hours to 1:00 saves successfully and changes the total to 4.75 |
| Delete | Row delete uses Redmine confirmation/DELETE handling; the test entry is removed and the total becomes 3.75 |
| CSV download | Browser downloads `timesheet.csv`; all 3 matching entries, decimal hours, Unicode text, version, and issue-less row are present |
| IIF download | Browser downloads `timesheet.iif`; one invoice and 3 lines; 429.76 receivable is balanced by -238.75, -119.38, and -71.63 |
| Permalink | Reopens the same filtered report and matching entry IDs |
| Session/reset | Filters persist while navigating; Reset restores default project grouping |
| Settings | List size and precision save successfully and are reflected in the report |
| Ordinary user, German | Only that user's matching 2.50-hour entry appears; administrator entries are absent; German labels and decimal comma render correctly |
| Custom date range | Editing the dates activates the custom-period radio button; the inclusive range returns the expected entry |
| Browser console | No warning/error messages observed during the final workflows |

The post-edit redirect returns to the Timesheet filter form with saved filters; clicking Apply refreshes the report. This also applies after deletion.

### Print layout

A temporary local preview was generated from the actual rendered date report, applying the same `all` and `print` stylesheets to make print styling inspectable in the integrated browser. Both collapsed date groups became visible, with week 42 and the correct daily totals. The right edges of the week/day-total cells matched the Hours header exactly in both tables. Selection controls, edit/delete actions, and expansion arrows were hidden. A screenshot was saved locally during validation.

This validates the print stylesheet and visible content. Physical printing, printer-specific pagination, and a particular printer driver were not tested.

## Corrections verified

- Replaced removed Rails helpers and old image references with supported links and SVG icons.
- Added accessible control names and horizontal table scrolling.
- Fixed the period radio values, jQuery property updates, session date serialization, reset link, and missing all-time translation.
- Unified permission checks so changing grouping or format cannot expose other users or private projects.
- Fixed group membership filtering for Redmine's User/Group shared-table model.
- Preserved entries without issues, prevented private issue metadata leakage, and removed premature total rounding.
- Fixed group/date CSV exports and overlapping-group totals/export duplication.
- Converted Redmine's rational hour values to decimal CSV/IIF quantities.
- Removed obsolete riif templates and hard-coded field 10, and added numeric hourly-rate configuration, validation, and field visibility checks.
- Aligned printed week numbers and daily totals with the Hours column and expanded collapsed groups in print.
- Removed duplicate context-menu asset includes.

## Limits and unrelated findings

- The complete application's repeated initialization encounters an existing Contacts/Helpdesk reload error (`RedmineHelpdesk::Patches::SettingsControllerPatch`). The Timesheet reload script isolates this plugin's initializer and preserves other plugins' setting getters required by their persistent model patches. All three Timesheet cycles pass; full-stack hot reload is not certified by this report.
- QuickBooks import was not executed in a QuickBooks installation. File structure, quantities, and balanced amounts were checked; accounting-specific customer/account mappings and encoding still need review in the target product.
- Other Redmine versions, database adapters, browser engines, external hook integrations, and very large data volumes were not tested.

No Timesheet defect remained in the covered workflows. Browser fixture projects, users, groups, roles, fields, and entries were removed after testing; plugin settings were restored. Existing application records and unrelated repositories were not intentionally changed.
