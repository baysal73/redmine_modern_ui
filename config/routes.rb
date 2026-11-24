# frozen_string_literal: true

base = RedmineModernUi.base_path

get base, to: 'modern_ui#index', as: :modern_ui
get "#{base}/api/me", to: 'modern_ui#me'
scope "#{base}/api", module: 'modern_ui/api', as: 'modern_ui_api' do
  get 'meta', to: 'meta#show'
  get 'home', to: 'home#show'
  get 'projects', to: 'projects#index'
  get 'projects/:id/assignees', to: 'projects#assignees'
  get 'projects/:id/new_issue_options', to: 'projects#new_issue_options'
  post 'issues', to: 'issues#create'
  get 'issues', to: 'issues#index'
  get 'issues/:id', to: 'issues#show', constraints: { id: /\d+/ }
  get 'issues/:id/form', to: 'issues#form', constraints: { id: /\d+/ }
  get 'issues/:id/options', to: 'issues#options', constraints: { id: /\d+/ }
  patch 'issues/:id', to: 'issues#update', constraints: { id: /\d+/ }
end
# SPA client-side routes: everything below the base path renders the same shell
get "#{base}/*path", to: 'modern_ui#index', constraints: ->(req) { !req.path.start_with?("/#{base}/api/") && req.path !~ /\.\w+\z/ }
