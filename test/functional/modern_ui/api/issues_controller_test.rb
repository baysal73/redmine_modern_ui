# frozen_string_literal: true

require_relative '../../../test_helper'

class ModernUi::Api::IssuesControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  # ---- authentication ----------------------------------------------------------------------------

  def test_anonymous_gets_json_401_not_a_redirect
    get :index
    assert_response :unauthorized
    assert json['error'].present?
  end

  # ---- list: visibility ----------------------------------------------------------------------------

  def test_list_only_contains_visible_issues
    [2, 3, 9].each do |uid|
      log_in uid
      get :index, params: { status: 'all', per_page: 100 }
      assert_response :success
      visible = Issue.visible(User.find(uid)).pluck(:id)
      assert_equal visible.size, json['total'], "total for user #{uid}"
      assert_empty json['issues'].map { |i| i['id'] } - visible, "invisible issue leaked to user #{uid}"
    end
  end

  def test_private_project_issues_are_hidden_from_non_members
    private_issue = Issue.where(project_id: 2).first
    log_in 3 # not a member of the private project 2
    get :show, params: { id: private_issue.id }
    assert_response :not_found
    log_in 2
    get :show, params: { id: private_issue.id }
    assert_response :success
  end

  def test_project_by_identifier_and_by_id
    log_in 2
    get :index, params: { project_id: 'ecookbook', status: 'all', per_page: 100 }
    assert_response :success
    by_identifier = json['total']
    get :index, params: { project_id: 1, status: 'all', per_page: 100 }
    assert_equal by_identifier, json['total']
  end

  def test_invisible_project_is_404_not_403
    log_in 3
    get :index, params: { project_id: 'onlinestore' }
    assert_response :not_found
  end

  # ---- list: filters, sorting, paging -----------------------------------------------------------------

  def test_status_filters
    log_in 2
    get :index, params: { status: 'open', per_page: 100 }
    assert json['issues'].none? { |i| i['status']['is_closed'] }
    get :index, params: { status: 'closed', per_page: 100 }
    assert json['issues'].all? { |i| i['status']['is_closed'] }
    get :index, params: { status: 'all', per_page: 100 }
    all = json['total']
    get :index, params: { status: 'open', per_page: 100 }
    open = json['total']
    get :index, params: { status: 'closed', per_page: 100 }
    assert_equal all, open + json['total']
  end

  def test_tracker_and_search_filters
    log_in 2
    get :index, params: { status: 'all', tracker_id: 1, per_page: 100 }
    assert json['issues'].all? { |i| i['tracker']['id'] == 1 }
    get :index, params: { status: 'all', q: 'Cannot print', per_page: 100 }
    assert json['issues'].any?
    assert json['issues'].all? { |i| i['subject'].downcase.include?('cannot print') }
  end

  def test_assigned_to_none_and_me
    log_in 2
    get :index, params: { status: 'all', assigned_to_id: 'none', per_page: 100 }
    assert json['issues'].all? { |i| i['assigned_to'].nil? }
    get :index, params: { status: 'all', assigned_to_id: 'me', per_page: 100 }
    assert json['issues'].all? { |i| i['assigned_to']&.fetch('id') == 2 }
  end

  def test_sorting_and_unknown_sort_columns_are_ignored
    log_in 2
    get :index, params: { status: 'all', sort: 'id:asc', per_page: 100 }
    ids = json['issues'].map { |i| i['id'] }
    assert_equal ids.sort, ids
    get :index, params: { status: 'all', sort: 'id:desc', per_page: 100 }
    ids = json['issues'].map { |i| i['id'] }
    assert_equal ids.sort.reverse, ids
    get :index, params: { sort: 'users.password:asc;DROP TABLE issues' }
    assert_response :success
  end

  def test_paging_and_per_page_cap
    log_in 2
    get :index, params: { status: 'all', per_page: 2, page: 2 }
    assert_equal 2, json['per_page']
    assert_equal 2, json['page']
    assert_operator json['issues'].size, :<=, 2
    get :index, params: { status: 'all', per_page: 100_000 }
    assert_equal 100, json['per_page']
  end

  # ---- detail ----------------------------------------------------------------------------------------

  def test_show_returns_workflow_and_permission_data
    log_in 2
    get :show, params: { id: 1 }
    assert_response :success
    issue = json['issue']
    assert_equal 1, issue['id']
    assert issue['allowed_statuses'].any?
    assert_equal true, issue['permissions']['edit']
    assert issue.key?('description_html')
    assert_kind_of Array, issue['journals']
  end

  def test_show_hides_private_notes_from_users_without_permission
    journal = Journal.create!(journalized: Issue.find(1), user: User.find(2), notes: 'secret', private_notes: true)
    log_in 3
    get :show, params: { id: 1 }
    assert_not_includes json['issue']['journals'].map { |j| j['id'] }, journal.id
    log_in 2
    get :show, params: { id: 1 }
    assert_includes json['issue']['journals'].map { |j| j['id'] }, journal.id
  end

  def test_redmine_links_in_texts_resolve_outside_the_api_namespace
    Issue.find(1).update_column(:description, 'see r2, #2, wiki [[CookBook documentation]] and source:/test/file.rb')
    log_in 2
    get :show, params: { id: 1 }
    assert_response :success
    assert_match %r{/issues/2}, json['issue']['description_html']
  end

  def test_multi_user_custom_fields_are_rendered_as_plain_names
    cf = IssueCustomField.create!(name: 'Reviewers', field_format: 'user', multiple: true, is_for_all: true,
                                  tracker_ids: Tracker.pluck(:id), visible: true)
    issue = Issue.find(1)
    issue.custom_field_values = { cf.id.to_s => %w[2 3] }
    issue.save!
    log_in 2
    get :show, params: { id: 1 }
    value = json['issue']['custom_fields'].find { |f| f['id'] == cf.id }['value']
    assert_includes value, User.find(2).name
    assert_includes value, User.find(3).name
    assert_no_match(/#<|hashed_password|User id/, value)
  end

  def test_safe_html_removes_dangerous_markup_but_keeps_formatting
    html = RedmineModernUi::Serializers.safe_html(
      '<p>hi <strong>bold</strong></p><script>alert(1)</script><iframe src="http://evil.example"></iframe>' \
      '<img src="x" onerror="alert(2)"><a href="javascript:alert(3)">x</a><ul><li>one</li></ul>' \
      '<table><tr><td>cell</td></tr></table>'
    )
    assert_no_match(/<script|<iframe|onerror|javascript:/i, html)
    assert_match(%r{<strong>bold</strong>}, html)
    assert_match(%r{<li>one</li>}, html)
    assert_match(%r{<td>cell</td>}, html)
  end

  def test_description_is_rendered_by_redmine_and_sanitized
    issue = Issue.find(1)
    issue.update_column(:description, "hello <script>alert(1)</script> *bold*")
    log_in 2
    get :show, params: { id: 1 }
    html = json['issue']['description_html']
    assert_no_match(/<script/i, html)
  end

  # ---- update ----------------------------------------------------------------------------------------

  def test_update_changes_fields_and_writes_a_journal
    log_in 2
    assert_difference 'Journal.count', 1 do
      patch :update, params: { id: 1, issue: { priority_id: 5, due_date: '2030-01-02' } }
    end
    assert_response :success
    assert_equal 5, Issue.find(1).priority_id
    assert_equal Date.new(2030, 1, 2), Issue.find(1).due_date
  end

  def test_update_respects_the_workflow
    issue = Issue.find(1)
    WorkflowTransition.where(tracker_id: issue.tracker_id, old_status_id: issue.status_id).delete_all
    log_in 2
    target = (IssueStatus.pluck(:id) - [issue.status_id]).first
    patch :update, params: { id: 1, issue: { status_id: target } }
    assert_response :unprocessable_content
    assert_equal issue.status_id, Issue.find(1).status_id
  end

  def test_update_with_invalid_value_returns_validation_errors
    log_in 2
    patch :update, params: { id: 1, issue: { due_date: 'nonsense' } }
    assert_response :unprocessable_content
    assert json['errors'].any?
  end

  def test_update_requires_edit_permission
    Role.find(2).remove_permission!(:edit_issues)
    log_in 3
    patch :update, params: { id: 1, issue: { priority_id: 5 } }
    assert_response :forbidden
  end

  def test_comment_only_needs_add_issue_notes
    Role.find(2).remove_permission!(:edit_issues)
    log_in 3
    assert_difference 'Journal.count', 1 do
      patch :update, params: { id: 1, issue: { notes: 'a comment' } }
    end
    assert_response :success
    assert_equal 'a comment', Journal.order(:id).last.notes
  end

  def test_comment_is_refused_without_permission
    Role.find(2).remove_permission!(:add_issue_notes)
    Role.find(2).remove_permission!(:edit_issues)
    log_in 3
    assert_no_difference 'Journal.count' do
      patch :update, params: { id: 1, issue: { notes: 'nope' } }
    end
    assert_response :forbidden
  end

  def test_blank_comment_is_rejected
    log_in 2
    patch :update, params: { id: 1, issue: { notes: '   ' } }
    assert_response :unprocessable_content
  end

  def test_private_notes_need_the_permission
    Role.find(2).remove_permission!(:set_notes_private)
    log_in 3
    patch :update, params: { id: 1, issue: { notes: 'x', private_notes: 'true' } }
    assert_equal false, Journal.order(:id).last.private_notes
  end

  def test_update_of_invisible_issue_is_404
    private_issue = Issue.where(project_id: 2).first
    log_in 3
    patch :update, params: { id: private_issue.id, issue: { priority_id: 5 } }
    assert_response :not_found
  end

  def test_options_lists_workflow_statuses_and_assignees
    log_in 2
    get :options, params: { id: 1 }
    assert_response :success
    assert json['allowed_statuses'].any?
    assert json['assignees'].any?
    assert json['priorities'].any?
  end

  # ---- full edit form ----------------------------------------------------------------------------------

  def test_form_describes_editable_fields_choices_and_custom_fields
    cf = IssueCustomField.create!(name: 'Kind', field_format: 'list', possible_values: %w[A B], is_for_all: true,
                                  tracker_ids: Tracker.pluck(:id), visible: true)
    log_in 2
    get :form, params: { id: 1 }
    assert_response :success
    assert_includes json['editable'], 'subject'
    assert_equal Issue.find(1).subject, json['values']['subject']
    assert json['options']['statuses'].any?
    field = json['custom_fields'].find { |f| f['id'] == cf.id }
    assert_equal 'select', field['kind']
    assert_equal %w[A B], field['options'].map { |o| o['value'] }
  end

  def test_form_is_refused_without_edit_permission
    Role.find(2).remove_permission!(:edit_issues)
    log_in 3
    get :form, params: { id: 1 }
    assert_response :forbidden
  end

  def test_form_hides_fields_that_the_workflow_makes_read_only
    WorkflowPermission.create!(role_id: 1, tracker_id: 1, old_status_id: 1, field_name: 'due_date', rule: 'readonly')
    log_in 2
    get :form, params: { id: 1 }
    assert_not_includes json['editable'], 'due_date' if Issue.find(1).tracker_id == 1 && Issue.find(1).status_id == 1
  end

  def test_update_changes_extended_fields_and_custom_fields
    cf = IssueCustomField.create!(name: 'Kind', field_format: 'list', possible_values: %w[A B], is_for_all: true,
                                  tracker_ids: Tracker.pluck(:id), visible: true)
    log_in 2
    patch :update, params: { id: 1, issue: { subject: 'Renamed', estimated_hours: 3.5, custom_field_values: { cf.id.to_s => 'B' } } }
    assert_response :success
    issue = Issue.find(1)
    assert_equal 'Renamed', issue.subject
    assert_equal 3.5, issue.estimated_hours
    assert_equal 'B', issue.custom_field_value(cf)
  end

  def test_update_ignores_custom_fields_the_user_may_not_edit
    cf = IssueCustomField.create!(name: 'Secret', field_format: 'string', is_for_all: true,
                                  tracker_ids: Tracker.pluck(:id), visible: false, role_ids: [1], editable: false)
    log_in 3 # developer: role 2 is not in role_ids
    patch :update, params: { id: 1, issue: { custom_field_values: { cf.id.to_s => 'hacked' } } }
    assert_not_equal 'hacked', Issue.find(1).custom_field_value(cf)
  end

  # ---- create ----------------------------------------------------------------------------------------

  def test_create_issue
    log_in 2
    assert_difference 'Issue.count', 1 do
      post :create, params: { issue: { project_id: 1, tracker_id: 1, subject: 'New one', priority_id: 5 } }
    end
    assert_response :created
    issue = Issue.order(:id).last
    assert_equal 'New one', issue.subject
    assert_equal 2, issue.author_id
    assert_equal 1, issue.project_id
  end

  def test_create_requires_the_add_issues_permission
    Role.find(2).remove_permission!(:add_issues)
    log_in 3
    assert_no_difference 'Issue.count' do
      post :create, params: { issue: { project_id: 1, tracker_id: 1, subject: 'x' } }
    end
    assert_response :forbidden
  end

  def test_create_in_invisible_project_is_404
    log_in 3
    post :create, params: { issue: { project_id: 2, subject: 'x' } }
    assert_response :not_found
  end

  def test_create_without_subject_returns_errors_and_classic_link
    log_in 2
    post :create, params: { issue: { project_id: 1, tracker_id: 1, subject: '' } }
    assert_response :unprocessable_content
    assert_match %r{/projects/ecookbook/issues/new}, json['classic_url']
  end


  # ---- bulk ------------------------------------------------------------------------------------------

  def test_bulk_updates_visible_editable_issues
    log_in 2
    post :bulk, params: { ids: [1, 2], issue: { priority_id: 5 } }
    assert_response :success
    assert_equal [1, 2], json['updated'].map { |i| i['id'] }.sort
    assert_equal [5, 5], Issue.where(id: [1, 2]).pluck(:priority_id)
  end

  def test_bulk_reports_issues_that_cannot_be_changed
    log_in 2
    # issue 4 is not editable for the workflow here: 99999 does not exist, private issue of another project is invisible
    post :bulk, params: { ids: [1, 99_999], issue: { priority_id: 5 } }
    assert_response :success
    assert_equal [1], json['updated'].map { |i| i['id'] }
    assert_equal [99_999], json['failed'].map { |f| f['id'] }
  end

  def test_bulk_respects_workflow
    WorkflowTransition.where(role_id: 1).delete_all
    log_in 2
    post :bulk, params: { ids: [1], issue: { status_id: 3 } }
    assert_response :success
    assert_empty json['updated']
    assert_equal 1, json['failed'].size
    assert_not_equal 3, Issue.find(1).status_id
  end

  def test_bulk_requires_login_and_csrf_free_json_error
    post :bulk, params: { ids: [1], issue: { priority_id: 5 } }
    assert_response :unauthorized
  end

  def test_bulk_without_ids_or_changes_is_rejected
    log_in 2
    post :bulk, params: { ids: [], issue: { priority_id: 5 } }
    assert_response :unprocessable_content
    post :bulk, params: { ids: [1], issue: { subject: 'x' } }
    assert_response :unprocessable_content
  end

  def test_bulk_limits_batch_size
    log_in 2
    post :bulk, params: { ids: (1..101).to_a, issue: { priority_id: 5 } }
    assert_response :unprocessable_content
  end

  # ---- configurable "done" statuses ------------------------------------------------------------------

  def test_done_statuses_are_treated_as_closed_in_open_filter_and_status_json
    log_in 2
    get :index, params: { status: 'open', per_page: 100 }
    open_before = json['total']
    in_progress = IssueStatus.find(2) # open in the fixtures
    count = Issue.visible(User.find(2)).where(status_id: in_progress.id).count
    assert_operator count, :>, 0
    with_plugin_settings('done_status_ids' => [in_progress.id.to_s]) do
      get :index, params: { status: 'open', per_page: 100 }
      assert_equal open_before - count, json['total']
      assert_not_includes json['issues'].map { |i| i['status']['id'] }, in_progress.id
      get :index, params: { status: 'all', per_page: 100 }
      row = json['issues'].find { |i| i['status']['id'] == in_progress.id }
      assert row['status']['is_closed']
    end
  end
end
