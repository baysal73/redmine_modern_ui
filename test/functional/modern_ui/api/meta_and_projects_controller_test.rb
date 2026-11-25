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
