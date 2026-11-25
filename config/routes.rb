# frozen_string_literal: true

base = RedmineModernUi.base_path

get base, to: 'modern_ui#index', as: :modern_ui
get "#{base}/api/me", to: 'modern_ui#me'
get "#{base}/api/logo", to: 'modern_ui#logo'
scope "#{base}/api", module: 'modern_ui/api', as: 'modern_ui_api' do
  get 'meta', to: 'meta#show'
  get 'home', to: 'home#show'
  get 'editor', to: 'editor#show'
  get 'projects', to: 'projects#index'
  get 'projects/:id/assignees', to: 'projects#assignees'
  get 'projects/:id/new_issue_options', to: 'projects#new_issue_options'
  post 'issues', to: 'issues#create'
  post 'uploads', to: 'uploads#create'
  post 'issues/bulk', to: 'issues#bulk'
  get 'issues', to: 'issues#index'
  get 'contacts', to: 'contacts#index'
  post 'contacts', to: 'contacts#create'
  get 'contacts/options', to: 'contacts#options'
  get 'contacts/:id', to: 'contacts#show', constraints: { id: /\d+/ }
  patch 'contacts/:id', to: 'contacts#update', constraints: { id: /\d+/ }
  post 'contacts/:id/notes', to: 'contacts#add_note', constraints: { id: /\d+/ }
  get 'products', to: 'products#index'
  get 'products/options', to: 'products#options'
  post 'products', to: 'products#create'
  get 'products/:id', to: 'products#show', constraints: { id: /\d+/ }
  patch 'products/:id', to: 'products#update', constraints: { id: /\d+/ }
  delete 'products/:id', to: 'products#destroy', constraints: { id: /\d+/ }
  get 'invoices', to: 'invoices#index'
  get 'invoices/options', to: 'invoices#options'
  get 'invoices/new', to: 'invoices#new_defaults'
  post 'invoices', to: 'invoices#create'
  get 'invoices/:id', to: 'invoices#show', constraints: { id: /\d+/ }
  get 'invoices/:id/form', to: 'invoices#form', constraints: { id: /\d+/ }
  patch 'invoices/:id', to: 'invoices#update', constraints: { id: /\d+/ }
  delete 'invoices/:id', to: 'invoices#destroy', constraints: { id: /\d+/ }
  post 'invoices/:id/payments', to: 'invoices#add_payment', constraints: { id: /\d+/ }
  delete 'invoices/:id/payments/:payment_id', to: 'invoices#remove_payment', constraints: { id: /\d+/, payment_id: /\d+/ }
  get 'report_templates', to: 'reports#templates'
  get 'issues/:id', to: 'issues#show', constraints: { id: /\d+/ }
  get 'issues/:id/form', to: 'issues#form', constraints: { id: /\d+/ }
  get 'issues/:id/options', to: 'issues#options', constraints: { id: /\d+/ }
  patch 'issues/:id', to: 'issues#update', constraints: { id: /\d+/ }
  delete 'issues/:id', to: 'issues#destroy', constraints: { id: /\d+/ }
end
# SPA client-side routes: everything below the base path renders the same shell
get "#{base}/*path", to: 'modern_ui#index', constraints: ->(req) { !req.path.start_with?("/#{base}/api/") && req.path !~ /\.\w+\z/ }
