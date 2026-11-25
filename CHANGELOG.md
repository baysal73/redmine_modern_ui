# Changelog

All notable changes are documented here. The project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Invoices: "Send by e-mail" dialog (recipient, subject and text with the plugin's macros, PDF attached by the plugin, optional "mark as sent"; needs `send_invoices`) and a visible PDF button.
- Bulk actions with checkboxes in the invoice, contact and product lists: set status (invoices, products), delete, CSV export of the selection. Every record is checked with the plugin's own permission rules and failures are reported per record.
- Calendar (when the events plugin plugin is installed): month and list view with events and dated tickets, search, category and "mine" filters, create / edit / delete events in a dialog (`g c`, sidebar button, Ctrl+K). Permissions and the Google Calendar sync stay in calendar_events; administrators get a "Sync with Google" button (`/app/api/calendar`). Dragging events is still classic-only.
- Branding in the plugin settings: upload a company logo (shown in the sidebar) and set three company colours (main, accent, grey). Empty = built-in colours.

### Added
- Ctrl/⌘ + K search over issues, contacts, invoices and projects (type `#123` to open an issue by number), with quick navigation when the box is empty. The classic "People" menu entry is hidden when Contacts is shown.
- Products (when the RedmineUP Products plugin is installed): "Add product" list when creating an invoice and for existing invoices (name, price, quantity 1 like the classic form); list with search, status/category filters; detail panel with click-to-edit fields, create and delete (a product used on orders or invoices cannot be deleted). Permissions (`view/add/edit/delete_products`) come from the plugin; the classic "Products" menu entry is hidden; also in Ctrl+K and `g p` (`/app/api/products`). Picture and bundle contents stay classic-only.
- "New contact" and "New invoice" buttons under "New issue" in the sidebar (only for users who may add them).
- Delete issues and invoices from the detail panel, only for users who have the permission (`delete_issues`; the Invoices plugin's own `destroyable_by?`). Always with a confirmation; issues with logged time stay classic-only, subtasks need a second confirmation.
- Invoices (when the RedmineUP Invoices plugin is installed): list with search, status/overdue/project filters and totals per currency; detail panel with click-to-edit header fields, items (edit, add, remove), recording and removing payments (incl. Finance account/category) and undo. All calculations, balance/status and bookkeeping run in the plugin's own models; every write checks the plugin's permissions and a version token (409 on concurrent changes). New invoices can be created from the list (project, contact search, number suggested by the plugin's number format, items with tax); the plugin validates and calculates. The number of an existing invoice, its contact, project and currency stay in the classic view (`/app/api/invoices`).
- Contacts (when the RedmineUP Contacts plugin is installed): searchable, filterable list (type, mine, list custom fields), detail panel with click-to-edit fields incl. address, tags and custom fields, notes with type, related deals/issues/employees, quick create, undo. Permissions come from the plugin (`/app/api/contacts`).
- Reports via the Redmine Reporter plugin (when installed): a "Report" menu on the issue list (selected issues, or the current page) and in each issue lists the user's report templates and opens the plugin's own preview/download page, so templates, prompts, e-mailing and permissions are exactly as in the classic UI (`GET /app/api/report_templates`).
- Undo: every saved field change, inline edit and bulk edit offers "Undo" in the toast (and Ctrl/⌘ + Z outside text fields).
- Every editable field in the issue panel is edited in place: click to edit, click away to save (Enter saves, Esc cancels); subject, description, dates, % done, category, version, estimated time, private flag and custom fields.
- Multi-value fields (e.g. participants) use a searchable chip picker instead of a `<select multiple>`; adding one value no longer means re-selecting all others.
- Rich text: when Redmine's text formatting is CKEditor (redmine_ckeditor), descriptions and comments use that same editor (`GET /app/api/editor`), so content is stored and shown identically in the classic UI. Other formats get a plain textarea.
- Attachments: pick, drop or paste files in the comment box and the quick-create dialog (`POST /app/api/uploads`, then `uploads` on create/update; only the user's own uploads can be attached).
- Setting "Statuses counted as done": lets the new UI treat statuses as finished that Redmine does not flag as closed.
- Filter chips with "Add filter" (multi-select status, tracker, priority, assignee; single project, due), person search.
- Grouping (status, priority, assignee, project, tracker) and saved views (stored in the browser).
- Bulk edit (`POST /app/api/issues/bulk`): status, assignee, priority, due date for up to 100 selected issues, workflow aware.
- Start page "My week" (`GET /app/api/home`), sidebar navigation with links to Redmine's other menus.
- `GET /app/api/issues/:id/form` (editable fields, workflow-aware choices, custom fields) feeds the in-place editing.
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
