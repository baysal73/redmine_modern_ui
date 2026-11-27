# frozen_string_literal: true

base = RedmineModernUi.base_path

get base, to: 'modern_ui#index', as: :modern_ui
get "#{base}/api/me", to: 'modern_ui#me'
get "#{base}/api/logo", to: 'modern_ui#logo'
scope "#{base}/api", module: 'modern_ui/api', as: 'modern_ui_api' do
  get 'meta', to: 'meta#show'
  get 'home', to: 'home#show'
  get 'home/layout', to: 'home#layout'
  put 'home/layout', to: 'home#update_layout'
  delete 'home/layout', to: 'home#reset_layout'
  get 'editor', to: 'editor#show'
  get 'projects', to: 'projects#index'
  get 'projects/:id/assignees', to: 'projects#assignees'
  get 'projects/:id/new_issue_options', to: 'projects#new_issue_options'
  post 'issues', to: 'issues#create'
  post 'uploads', to: 'uploads#create'
  post 'issues/bulk', to: 'issues#bulk'
  get 'issues', to: 'issues#index'
  get 'issues/filters', to: 'issues#filters'
  get 'issues/filter_values', to: 'issues#filter_values'
  get 'issues/queries', to: 'issues#queries'
  post 'issues/queries', to: 'issues#create_query'
  delete 'issues/queries/:id', to: 'issues#destroy_query', constraints: { id: /\d+/ }
  get 'contacts', to: 'contacts#index'
  get 'contacts/filters', to: 'contacts#filters'
  get 'contacts/filter_values', to: 'contacts#filter_values'
  get 'contacts/queries', to: 'contacts#queries'
  post 'contacts/queries', to: 'contacts#create_query'
  delete 'contacts/queries/:id', to: 'contacts#destroy_query', constraints: { id: /\d+/ }
  post 'contacts', to: 'contacts#create'
  post 'contacts/bulk', to: 'contacts#bulk'
  get 'contacts/options', to: 'contacts#options'
  get 'contacts/:id', to: 'contacts#show', constraints: { id: /\d+/ }
  patch 'contacts/:id', to: 'contacts#update', constraints: { id: /\d+/ }
  post 'contacts/:id/notes', to: 'contacts#add_note', constraints: { id: /\d+/ }
  get 'calendar', to: 'calendar#index'
  post 'calendar/events', to: 'calendar#create'
  patch 'calendar/events/:id', to: 'calendar#update', constraints: { id: /\d+/ }
  delete 'calendar/events/:id', to: 'calendar#destroy', constraints: { id: /\d+/ }
  post 'calendar/sync', to: 'calendar#sync'
  get 'products', to: 'products#index'
  get 'products/filters', to: 'products#filters'
  get 'products/filter_values', to: 'products#filter_values'
  get 'products/queries', to: 'products#queries'
  post 'products/queries', to: 'products#create_query'
  delete 'products/queries/:id', to: 'products#destroy_query', constraints: { id: /\d+/ }
  get 'products/options', to: 'products#options'
  post 'products', to: 'products#create'
  post 'products/bulk', to: 'products#bulk'
  get 'products/:id', to: 'products#show', constraints: { id: /\d+/ }
  patch 'products/:id', to: 'products#update', constraints: { id: /\d+/ }
  delete 'products/:id', to: 'products#destroy', constraints: { id: /\d+/ }
  get 'invoices', to: 'invoices#index'
  get 'invoices/filters', to: 'invoices#filters'
  get 'invoices/filter_values', to: 'invoices#filter_values'
  get 'invoices/queries', to: 'invoices#queries'
  post 'invoices/queries', to: 'invoices#create_query'
  delete 'invoices/queries/:id', to: 'invoices#destroy_query', constraints: { id: /\d+/ }
  get 'invoices/options', to: 'invoices#options'
  get 'invoices/new', to: 'invoices#new_defaults'
  post 'invoices', to: 'invoices#create'
  post 'invoices/bulk', to: 'invoices#bulk'
  get 'invoices/:id', to: 'invoices#show', constraints: { id: /\d+/ }
  get 'invoices/:id/form', to: 'invoices#form', constraints: { id: /\d+/ }
  patch 'invoices/:id', to: 'invoices#update', constraints: { id: /\d+/ }
  get 'invoices/:id/mail', to: 'invoices#mail', constraints: { id: /\d+/ }
  post 'invoices/:id/send_mail', to: 'invoices#send_mail', constraints: { id: /\d+/ }
  delete 'invoices/:id', to: 'invoices#destroy', constraints: { id: /\d+/ }
  post 'invoices/:id/payments', to: 'invoices#add_payment', constraints: { id: /\d+/ }
  delete 'invoices/:id/payments/:payment_id', to: 'invoices#remove_payment', constraints: { id: /\d+/, payment_id: /\d+/ }
  get 'documents', to: 'documents#index'
  get 'documents/projects', to: 'documents#projects'
  post 'documents/folders', to: 'documents#create_folder'
  patch 'documents/folders/:id', to: 'documents#update_folder', constraints: { id: /\d+/ }
  delete 'documents/folders/:id', to: 'documents#destroy_folder', constraints: { id: /\d+/ }
  post 'documents/folders/:id/restore', to: 'documents#restore_folder', constraints: { id: /\d+/ }
  post 'documents/files', to: 'documents#create_files'
  get 'documents/files/:id', to: 'documents#show_file', constraints: { id: /\d+/ }
  delete 'documents/files/:id', to: 'documents#destroy_file', constraints: { id: /\d+/ }
  post 'documents/files/:id/restore', to: 'documents#restore_file', constraints: { id: /\d+/ }
  get 'report_templates', to: 'reports#templates'
  get 'issues/:id', to: 'issues#show', constraints: { id: /\d+/ }
  get 'issues/:id/form', to: 'issues#form', constraints: { id: /\d+/ }
  get 'issues/:id/options', to: 'issues#options', constraints: { id: /\d+/ }
  patch 'issues/:id', to: 'issues#update', constraints: { id: /\d+/ }
  delete 'issues/:id', to: 'issues#destroy', constraints: { id: /\d+/ }
end
# SPA client-side routes: everything below the base path renders the same shell
get "#{base}/*path", to: 'modern_ui#index', constraints: ->(req) { !req.path.start_with?("/#{base}/api/") && req.path !~ /\.\w+\z/ }
