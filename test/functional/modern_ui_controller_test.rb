# frozen_string_literal: true

require_relative '../test_helper'

class ModernUiControllerTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  fixtures(*FIXTURES)

  def test_index_redirects_anonymous_users_to_login
    get :index
    assert_response :redirect
    assert_match %r{/login}, response.location
    assert_match 'back_url', response.location
  end

  def test_index_renders_the_app_shell_for_logged_in_users
    log_in 2
    get :index
    assert_response :success
    assert_select 'div#app[data-config]'
    assert_select 'meta[name=csrf-token]'
    assert_select 'script[type=module]'
  end

  def test_shell_does_not_embed_an_api_key
    log_in 2
    get :index
    assert_no_match(/api[_-]?key/i, response.body)
  end

  def test_me_returns_the_current_user
    log_in 2
    get :me
    assert_response :success
    assert_equal 2, json['id']
    assert_equal 'jsmith', json['login']
  end

  def test_me_requires_login
    get :me
    assert_response :redirect
  end
end
