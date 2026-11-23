# frozen_string_literal: true

require_relative 'lib/redmine_modern_ui'

Redmine::Plugin.register :redmine_modern_ui do
  name 'Redmine Modern UI'
  author 'baysal73'
  description 'A fast, modern single-page interface for Redmine. Redmine stays the engine for data, permissions and workflow.'
  version RedmineModernUi::VERSION
  url 'https://github.com/baysal73/redmine_modern_ui'
  author_url 'https://github.com/baysal73'
  requires_redmine version_or_higher: '6.1.0'

  settings default: RedmineModernUi::DEFAULTS, partial: 'settings/redmine_modern_ui'

  # Link "New interface" in the classic top menu (the SPA links back itself).
  menu :top_menu, :modern_ui, { controller: 'modern_ui', action: 'index' },
       caption: :modern_ui_link_new_ui, if: proc { User.current.logged? }
end

RedmineModernUi.apply_patches!
Rails.application.config.to_prepare { RedmineModernUi.apply_patches! }
