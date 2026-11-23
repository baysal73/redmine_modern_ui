# frozen_string_literal: true

require_relative '../test_helper'

# After login users land on the new UI - unless they opted out, the admin disabled it, or a back_url is given.
class LoginRedirectTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  tests AccountController
  fixtures(*FIXTURES)

  def login(extra = {})
    post :login, params: { username: 'jsmith', password: 'jsmith' }.merge(extra)
  end

  def test_redirects_to_new_ui_by_default
    login
    assert_redirected_to '/app'
  end

  def test_back_url_wins
    login(back_url: 'http://test.host/issues/1')
    assert_redirected_to '/issues/1'
  end

  def test_global_switch_off_keeps_my_page
    with_plugin_settings('redirect_after_login' => '0') do
      login
      assert_redirected_to '/my/page'
    end
  end

  def test_user_can_opt_out
    user = User.find(2)
    user.pref[:modern_ui_redirect] = '0'
    user.pref.save!
    login
    assert_redirected_to '/my/page'
  end

  def test_other_users_are_not_affected_by_an_opt_out
    user = User.find(2)
    user.pref[:modern_ui_redirect] = '0'
    user.pref.save!
    post :login, params: { username: 'dlopper', password: 'foo' }
    assert_redirected_to '/app'
  end
end
