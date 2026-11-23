# Changelog

All notable changes are documented here. The project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-23

First public version.

### Added
- Single-page interface at `/app` (path configurable), served through Redmine's normal login and session.
- Issue table: filters (project, status, tracker, priority, assignee, search), sortable columns, column chooser,
  paging, shareable URLs, inline editing of status (workflow aware), priority, assignee and due date.
- Split view with issue details, history, attachments and comments (including private comments).
- Kanban board with workflow-aware drag and drop and a keyboard/touch friendly move menu.
- Quick-create dialog.
- Dark mode, responsive layout, keyboard shortcuts (`?` shows them), German, English and Turkish translations.
- Redirect after login to the new UI (global switch in the plugin settings, opt-out per user under "My account").
- Links between the classic and the new interface.
- JSON endpoints under `/app/api/` that reuse Redmine's visibility scopes, permissions and workflow rules.
