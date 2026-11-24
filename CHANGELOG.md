# Changelog

All notable changes are documented here. The project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Setting "Statuses counted as done": lets the new UI treat statuses as finished that Redmine does not flag as closed.
- Filter chips with "Add filter" (multi-select status, tracker, priority, assignee; single project, due), person search.
- Grouping (status, priority, assignee, project, tracker) and saved views (stored in the browser).
- Bulk edit (`POST /app/api/issues/bulk`): status, assignee, priority, due date for up to 100 selected issues, workflow aware.
- Start page "My week" (`GET /app/api/home`), sidebar navigation with links to Redmine's other menus.
- Edit dialog for all editable fields including custom fields (`GET /app/api/issues/:id/form`).
- Status, priority and avatar icons; due-date filter (overdue, this week, none).

### Changed
- New visual design based on Tailwind CSS (build time only) and Lucide icons.

### Fixed
- Custom field values were rendered as raw objects for multi-user fields.
- Redmine links in texts (e.g. `r2`) caused errors inside the namespaced API.
- Rendered HTML is sanitized once more on the server (formatter plugins may let tags like `<iframe>` through).
- Login redirect now works together with plugins that replace the landing page.

## [0.1.0] - 2026-11-23

First public version.

### Added
- Single-page interface at `/app` (path configurable), served through Redmine's normal login and session.
- Issue table: filters (project, status, tracker, priority, assignee, search), sortable columns, column chooser,
  paging, shareable URLs, inline editing of status (workflow aware), priority, assignee and due date.
- Split view with issue details, history, attachments and comments (including private comments).
- Quick-create dialog.
- Dark mode, responsive layout, keyboard shortcuts (`?` shows them), German, English and Turkish translations.
- Redirect after login to the new UI (global switch in the plugin settings, opt-out per user under "My account").
- Links between the classic and the new interface.
- JSON endpoints under `/app/api/` that reuse Redmine's visibility scopes, permissions and workflow rules.
