# frozen_string_literal: true

require_relative '../../../test_helper'

# The user's own start page layout (widgets), stored in the user preferences.
class ModernUi::Api::HomeLayoutTest < Redmine::ControllerTest
  tests ModernUi::Api::HomeController
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def setup
    @request.headers['Accept'] = 'application/json'
  end

  def test_no_layout_means_default
    log_in 2
    get :layout
    assert_response :success
    assert_nil json['widgets']
  end

  def test_save_cleans_and_stores_per_user
    log_in 2
    put :update_layout, params: { widgets: [
      { id: 'a1', type: 'overdue', size: 'l', limit: 99 },
      { id: 'bad id!', type: 'cal_week', size: 'huge' },
      { type: 'nope', size: 'm' },
      { type: 'query', size: 's' },
      { type: 'query', size: 's', query_id: '7' }
    ] }
    assert_response :success, response.body
    w = json['widgets']
    assert_equal %w[overdue cal_week query], w.map { |x| x['type'] }
    assert_equal({ 'id' => 'a1', 'type' => 'overdue', 'size' => 'l', 'limit' => 25 }, w[0])
    assert_equal 'm', w[1]['size']
    assert_match(/\A\h{8}\z/, w[1]['id'])
    assert_equal 7, w[2]['query_id']

    get :layout
    assert_equal w, json['widgets']
    assert_equal w, User.find(2).pref.reload[:modern_ui_home]

    log_in 3
    get :layout
    assert_nil json['widgets'], 'another user still has the default'
  end

  def test_reset_goes_back_to_default
    log_in 2
    put :update_layout, params: { widgets: [{ type: 'recent', size: 'full' }] }
    delete :reset_layout
    assert_response :no_content, response.body
    get :layout
    assert_nil json['widgets']
  end

  def test_needs_login
    get :layout
    assert_response :unauthorized
  end
end
