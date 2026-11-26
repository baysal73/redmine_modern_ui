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

  # Opening the plain address sends people to /login?back_url=/ - that is no deep link.
  {
    'the_start_address' => 'http://test.host/', 'a_relative_start_address' => '/',
    'my_page' => 'http://test.host/my/page', 'the_home_page' => 'http://test.host/home'
  }.each do |name, url|
    define_method("test_back_url_to_#{name}_still_lands_in_the_new_ui") do
      login(back_url: url)
      assert_redirected_to '/app'
    end
  end

  def test_back_url_to_a_specific_page_is_kept_even_with_a_query
    login(back_url: 'http://test.host/projects/ecookbook/issues?status_id=*')
    assert_redirected_to '/projects/ecookbook/issues?status_id=*'
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

  # Other plugins may replace the default landing page; the new UI still takes precedence when enabled.
  module OtherPluginLanding
    private

    def successful_authentication(user)
      self.logged_user = user
      call_hook(:controller_account_success_authentication_after, user: user)
      redirect_back_or_default projects_path(some_hint: 1)
    end
  end

  def test_works_together_with_plugins_that_replace_the_landing_page
    @controller.singleton_class.prepend(OtherPluginLanding) # this instance only, no leaking into other tests
    login
    assert_redirected_to '/app'
    with_plugin_settings('redirect_after_login' => '0') do
      login
      assert_redirected_to '/projects?some_hint=1'
    end
  end
end
