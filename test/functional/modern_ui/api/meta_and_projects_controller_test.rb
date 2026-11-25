# frozen_string_literal: true

require_relative '../../../test_helper'

class ModernUi::Api::MetaControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_meta_lists_people_for_the_assignee_filter_without_private_data
    log_in 2
    get :show
    users = JSON.parse(response.body)['users']
    assert users.any?
    assert_equal %w[id name], users.first.keys.sort
    assert_not_includes users.map { |u| u['id'] }, User.anonymous.id
  end

  def test_requires_login
    get :show
    assert_response :unauthorized
  end

  def test_documents_feature_is_off_without_dmsf
    skip 'DMSF is installed' if defined?(::DmsfFolder)
    log_in 2
    get :show
    assert_equal false, json['features']['documents']
  end

  def test_links_to_the_classic_menus_are_only_for_admins
    log_in 2
    get :show
    assert_empty json['classic_menu']
    assert_equal false, json['user']['admin']
    log_in 1
    get :show
    assert_equal true, json['user']['admin']
    assert_kind_of Array, json['classic_menu']
  end

  def test_meta_contains_reference_data_and_only_visible_projects
    log_in 3
    get :show
    assert_response :success
    assert_equal IssueStatus.count, json['statuses'].size
    assert_equal Tracker.count, json['trackers'].size
    visible = Project.visible(User.find(3)).active.pluck(:id)
    assert_empty json['projects'].map { |p| p['id'] } - visible
    assert_not_includes json['projects'].map { |p| p['identifier'] }, 'onlinestore'
    assert json['addable_project_ids'].all? { |id| json['projects'].any? { |p| p['id'] == id } }
  end
end

class ModernUi::Api::ProjectsControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_index_only_lists_visible_projects
    log_in 3
    get :index
    assert_response :success
    assert_not_includes json['projects'].map { |p| p['identifier'] }, 'onlinestore'
  end

  def test_assignees_of_an_invisible_project_is_404
    log_in 3
    get :assignees, params: { id: 'onlinestore' }
    assert_response :not_found
  end

  def test_new_issue_options_need_add_issues
    log_in 2
    get :new_issue_options, params: { id: 1 }
    assert_response :success
    assert json['trackers'].any?
    Role.find(2).remove_permission!(:add_issues)
    log_in 3
    get :new_issue_options, params: { id: 1 }
    assert_response :forbidden
  end
end

class ModernUi::Api::HomeControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_requires_login
    get :show
    assert_response :unauthorized
  end

  def test_overdue_and_due_soon_contain_only_my_open_visible_issues
    today = User.find(2).today
    visible_open = Issue.visible(User.find(2)).open.order(:id).to_a
    visible_open[0].update_columns(assigned_to_id: 2, due_date: today - 3)
    visible_open[1].update_columns(assigned_to_id: 2, due_date: today + 2)
    mine = Issue.visible(User.find(2)).open.where(assigned_to_id: 2)
    log_in 2
    get :show
    assert_response :success
    assert json['overdue'].any?
    mine_ids = [2] + User.find(2).group_ids # Redmine's "me" includes the user's groups
    assert json['overdue'].all? { |i| mine_ids.include?(i['assigned_to']['id']) && !i['status']['is_closed'] && Date.parse(i['due_date']) < today }
    assert json['due_soon'].all? { |i| (today..(today + 7)).cover?(Date.parse(i['due_date'])) }
    assert_operator json['counts']['assigned_open'], :>=, mine.count
  end

  def test_recent_only_contains_visible_issues
    log_in 3
    get :show
    visible = Issue.visible(User.find(3)).pluck(:id)
    assert_empty json['recent'].map { |i| i['id'] } - visible
  end
end

class ModernUi::Api::EditorControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_requires_login
    get :show
    assert_response :unauthorized
  end

  def test_plain_text_formatting_has_no_rich_editor
    log_in 2
    get :show
    assert_response :success
    assert_equal 'plain', JSON.parse(response.body)['kind']
  end
end

class ModernUi::Api::ReportsControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_requires_login
    get :templates
    assert_response :unauthorized
  end

  def test_reports_unavailable_without_the_reporter_plugin
    skip 'Reporter plugin installed' if defined?(::ReportTemplate)
    log_in 2
    get :templates
    assert_response :success
    assert_equal false, json['available']
    assert_empty json['templates']
  end
end

class ModernUi::Api::ContactsControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_requires_login
    get :index
    assert_response :unauthorized
  end

  # The CRM plugin is not part of the test image: without it the endpoints must not fail with a 500
  def test_not_found_without_the_crm_plugin
    skip 'CRM plugin installed' if defined?(::Contact)
    log_in 2
    get :index
    assert_response :not_found
    get :show, params: { id: 1 }
    assert_response :not_found
  end

  def test_meta_reports_contacts_feature_off_without_plugin
    skip 'CRM plugin installed' if defined?(::Contact)
    @controller = ModernUi::Api::MetaController.new
    log_in 2
    get :show
    assert_equal false, json['features']['contacts']
  end
end

class ModernUi::Api::InvoicesControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_requires_login
    get :index
    assert_response :unauthorized
  end

  def test_not_found_without_the_invoices_plugin
    skip 'Invoices plugin installed' if defined?(::Invoice)
    log_in 2
    get :index
    assert_response :not_found
  end
end

class ModernUi::Api::InvoiceWritesTest < Redmine::ControllerTest
  tests ModernUi::Api::InvoicesController
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_writes_require_login
    patch :update, params: { id: 1, invoice: { subject: 'x' } }
    assert_response :unauthorized
    post :add_payment, params: { id: 1, payment: { amount: '1' } }
    assert_response :unauthorized
    delete :remove_payment, params: { id: 1, payment_id: 1 }
    assert_response :unauthorized
    post :create, params: { invoice: { project_id: 1 } }
    assert_response :unauthorized
    get :new_defaults, params: { project_id: 1 }
    assert_response :unauthorized
    delete :destroy, params: { id: 1 }
    assert_response :unauthorized
  end

  def test_writes_not_found_without_the_invoices_plugin
    skip 'Invoices plugin installed' if defined?(::Invoice)
    log_in 2
    patch :update, params: { id: 1, invoice: { subject: 'x' } }
    assert_response :not_found
    post :create, params: { invoice: { project_id: 1 } }
    assert_response :not_found
    delete :destroy, params: { id: 1 }
    assert_response :not_found
  end
end

class ModernUi::Api::IssueDestroyTest < Redmine::ControllerTest
  tests ModernUi::Api::IssuesController
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_requires_login
    delete :destroy, params: { id: 1 }
    assert_response :unauthorized
  end

  def test_forbidden_without_delete_permission
    Role.find(1).remove_permission!(:delete_issues)
    log_in 2
    assert_no_difference 'Issue.count' do
      delete :destroy, params: { id: 1 }
    end
    assert_response :forbidden
  end

  def test_refuses_issues_with_logged_time
    Role.find(1).add_permission!(:delete_issues)
    log_in 2
    assert TimeEntry.where(issue_id: 1).exists?
    assert_no_difference 'Issue.count' do
      delete :destroy, params: { id: 1 }
    end
    assert_response :unprocessable_entity
  end

  def test_deletes_with_permission
    Role.find(1).add_permission!(:delete_issues)
    log_in 2
    issue = Issue.generate!(project_id: 1, subject: 'to delete')
    assert_difference 'Issue.count', -1 do
      delete :destroy, params: { id: issue.id }
    end
    assert_response :no_content
  end

  def test_subtasks_need_confirmation
    Role.find(1).add_permission!(:delete_issues)
    log_in 2
    parent = Issue.generate!(project_id: 1, subject: 'parent')
    Issue.generate!(project_id: 1, subject: 'child', parent_issue_id: parent.id)
    assert_no_difference 'Issue.count' do
      delete :destroy, params: { id: parent.id }
    end
    assert_response :conflict
    assert_difference 'Issue.count', -2 do
      delete :destroy, params: { id: parent.id, with_subtasks: '1' }
    end
  end
end

class ModernUi::Api::ProductsControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_requires_login
    get :index
    assert_response :unauthorized
    post :create, params: { product: { name: 'x' } }
    assert_response :unauthorized
    patch :update, params: { id: 1, product: { name: 'x' } }
    assert_response :unauthorized
    delete :destroy, params: { id: 1 }
    assert_response :unauthorized
    post :bulk, params: { ids: [1], op: 'delete' }
    assert_response :unauthorized
  end

  def test_not_found_without_the_products_plugin
    skip 'Products plugin installed' if defined?(::Product)
    log_in 2
    get :index
    assert_response :not_found
    post :create, params: { product: { name: 'x' } }
    assert_response :not_found
    delete :destroy, params: { id: 1 }
    assert_response :not_found
    post :bulk, params: { ids: [1], op: 'delete' }
    assert_response :not_found
  end
end

class ModernUi::Api::CalendarControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_requires_login
    get :index
    assert_response :unauthorized
    post :create, params: { title: 'x' }
    assert_response :unauthorized
    delete :destroy, params: { id: 1 }
    assert_response :unauthorized
    post :sync
    assert_response :unauthorized
  end

  def test_not_found_without_the_events_plugin
    skip 'events plugin plugin installed' if defined?(::CalendarEvent)
    log_in 2
    get :index
    assert_response :not_found
    post :create, params: { title: 'x' }
    assert_response :not_found
    post :sync
    assert_response :not_found
  end
end

class ModernUi::Api::DocumentsControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_requires_login
    get :index, params: { project: 'ecookbook' }
    assert_response :unauthorized
  end

  def test_answers_404_without_the_dmsf_plugin
    skip 'DMSF is installed' if defined?(::DmsfFile)
    log_in 2
    get :projects
    assert_response :not_found
    post :create_files, params: { project: 'ecookbook', uploads: [{ token: 'x' }] }
    assert_response :not_found
  end
end
