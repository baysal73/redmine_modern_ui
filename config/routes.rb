# frozen_string_literal: true

base = RedmineModernUi.base_path

get base, to: 'modern_ui#index', as: :modern_ui
get "#{base}/api/me", to: 'modern_ui#me'
# SPA client-side routes: everything below the base path renders the same shell
get "#{base}/*path", to: 'modern_ui#index', constraints: ->(req) { !req.path.start_with?("/#{base}/api/") && req.path !~ /\.\w+\z/ }
