# Contributing

Thanks for helping! Bug reports, translations and pull requests are welcome.

## Principles

- **No changes to the Redmine core.** Extend Redmine through hooks, our own controllers/routes and `prepend` patches.
- **Redmine stays the engine.** Permissions, visibility and workflow are decided by Redmine models
  (`Issue.visible`, `allowed_to?`, `safe_attributes`, `new_statuses_allowed_to`). Never re-implement them in the frontend.
- **No extra gems, no migrations** unless there is a very good reason (state it in the pull request).
- **No Node.js on the server.** The built frontend (`assets/`) is committed. Rebuild it before you commit changes in `frontend/`.
- No secrets, server paths or real user data in code, tests, screenshots or fixtures.

## Development setup

You need Docker (for a throw-away Redmine) and Node.js 18+.

```bash
# 1. Start a fresh Redmine 7 with demo data (SQLite, local only)
docker run -d --name mui-dev -p 127.0.0.1:3710:3000 \
  -e RAILS_ENV=production -e SECRET_KEY_BASE=dev-only-not-a-secret-0123456789abcdef0123456789abcdef \
  -v "$PWD":/usr/src/redmine/plugins/redmine_modern_ui redmine:7.0.3
docker exec mui-dev bash -c 'cd /usr/src/redmine && bundle exec rake redmine:load_default_data REDMINE_LANG=en \
  && bundle exec rails runner plugins/redmine_modern_ui/dev/seed.rb'
# Demo users: admin, alice (manager), bob (developer), cem and dana (reporters) - password DemoPassw0rd!2026

# 2. Build the frontend
cd frontend && npm install && npm run build        # single JS + CSS file into ../assets
docker restart mui-dev                              # Redmine (production mode) caches assets
```

Then open <http://127.0.0.1:3710/app>.

### Why one JS and one CSS file?

Redmine 7 serves plugin assets through Propshaft, which adds a content hash to every file name.
Relative imports between chunks would break, so the Vite build is configured as one bundle.

## Tests

```bash
# Frontend
cd frontend && npm run typecheck && npm test

# Plugin (inside a Redmine checkout with the test group installed)
RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=redmine_modern_ui
```

CI runs both against Redmine 6.1 and 7.0. Please add a test for every endpoint or permission rule you touch.

## Translations

- Frontend texts: `frontend/src/i18n/<lang>.ts` (copy `en.ts`, translate, register the language in `i18n/index.ts`).
- Redmine-side texts (settings, errors): `config/locales/<lang>.yml`.

## Commits and pull requests

English commit messages in the imperative mood ("Add board filter"). Keep pull requests focused.
By contributing you agree that your work is released under the GPL-2.0-or-later (see `LICENSE`).
