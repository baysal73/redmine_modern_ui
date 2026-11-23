# frozen_string_literal: true

require_relative '../../../test_helper'

class ModernUi::Api::MetaControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

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
