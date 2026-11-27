# frozen_string_literal: true

require_relative '../../../test_helper'

# Free filters (every filter Redmine's issue query offers) and the user's private saved filters.
class ModernUi::Api::IssueFiltersTest < Redmine::ControllerTest
  tests ModernUi::Api::IssuesController
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def setup
    @request.headers['Accept'] = 'application/json'
  end

  def test_lists_standard_and_custom_field_filters_with_operators
    log_in 2
    get :filters
    assert_response :success
    names = json['filters'].map { |f| f['name'] }
    assert_includes names, 'status_id'
    assert_includes names, 'due_date'
    assert names.any? { |n| n.start_with?('cf_') }, 'custom field filters are offered'
    due = json['filters'].find { |f| f['name'] == 'due_date' }
    assert(due['operators'].any? { |o| o['id'] == '><' })
    assert due['operators'].all? { |o| o['label'].present? }
  end

  def test_free_filter_narrows_the_list
    log_in 1
    filters = [{ field: 'done_ratio', op: '>=', values: ['50'] }].to_json
    get :index, params: { status: 'all', per_page: 100, filters: filters }
    assert_response :success
    assert_equal Issue.visible(User.find(1)).where('done_ratio >= 50').count, json['total']
  end

  def test_unknown_field_or_operator_is_ignored
    log_in 1
    get :index, params: { status: 'all', per_page: 100 }
    all = json['total']
    filters = [{ field: 'nope', op: '=', values: ['1'] }, { field: 'done_ratio', op: 'zz', values: ['1'] }].to_json
    get :index, params: { status: 'all', per_page: 100, filters: filters }
    assert_response :success
    assert_equal all, json['total']
  end

  def test_invalid_value_is_a_422_with_a_message
    log_in 1
    get :index, params: { status: 'all', filters: [{ field: 'due_date', op: '=', values: ['garbage'] }].to_json }
    assert_response :unprocessable_entity
    assert json['error'].present?
  end

  def test_save_list_and_delete_a_private_query
    log_in 2
    filters = [{ field: 'done_ratio', op: '>=', values: ['50'] }].to_json
    post :create_query, params: { name: 'Half done', status: 'all', tracker_id: '1', due: 'overdue', q: 'print', filters: filters, sort: 'id:asc' }
    assert_response :created
    id = json['query']['id']
    query = IssueQuery.find(id)
    assert_equal User.find(2), query.user
    assert_equal IssueQuery::VISIBILITY_PRIVATE, query.visibility
    assert_equal ['<t-', ['0']], [query.filters['due_date'][:operator], query.filters['due_date'][:values]], 'saved with relative dates'

    state = json['query']['state']
    assert_equal 'open', state['status'], 'overdue only ever lists open tickets'
    assert_equal '1', state['tracker']
    assert_equal 'overdue', state['due']
    assert_equal 'print', state['q']
    assert_equal 'id:asc', state['sort']
    assert_equal [{ 'field' => 'done_ratio', 'op' => '>=', 'values' => ['50'] }], JSON.parse(state['filters'])

    get :queries
    assert_includes json['queries'].map { |x| x['name'] }, 'Half done'

    # nobody else sees it or can delete it
    log_in 3
    get :queries
    assert_not_includes json['queries'].map { |x| x['id'] }, id
    delete :destroy_query, params: { id: id }
    assert_response :not_found
    assert IssueQuery.exists?(id)

    log_in 2
    delete :destroy_query, params: { id: id }
    assert_response :no_content
    assert_not IssueQuery.exists?(id)
  end

  def test_name_is_required
    log_in 2
    post :create_query, params: { name: ' ', status: 'all' }
    assert_response :unprocessable_entity
  end
end
