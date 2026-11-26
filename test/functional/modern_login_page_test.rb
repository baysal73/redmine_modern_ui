# frozen_string_literal: true

require_relative '../test_helper'

# The sign-in pages get a modern stylesheet; it is only added there, can be switched off and carries the brand colours.
class ModernLoginPageTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  tests AccountController
  fixtures(*FIXTURES)

  # Redmine 7.0 serves plugin assets as /assets/plugin_assets/<plugin>/login-<digest>.css, 6.1 as /plugin_assets/<plugin>/stylesheets/login.css
  STYLE = %r{redmine_modern_ui/(stylesheets/)?login[-.]}
  PIXEL = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAHsA4OQAAAABJRU5ErkJggg=='

  def test_login_page_gets_the_stylesheet
    get :login
    assert_response :success
    assert_match STYLE, response.body
  end

  def test_lost_password_page_gets_it_too
    get :lost_password
    assert_response :success
    assert_match STYLE, response.body
  end

  def test_can_be_switched_off
    with_plugin_settings('modern_login' => '0') do
      get :login
      assert_response :success
      refute_match STYLE, response.body
    end
  end

  def test_brand_colours_become_css_variables
    with_plugin_settings('brand_primary' => '#112233', 'brand_gold' => '#aabbcc') do
      get :login
      assert_includes response.body, '--mui-primary:#112233'
      assert_includes response.body, '--mui-gold:#aabbcc'
    end
  end

  def test_invalid_colours_are_not_written_into_the_page
    with_plugin_settings('brand_primary' => 'red;}</style><script>alert(1)</script>') do
      get :login
      refute_includes response.body, '<script>alert(1)'
      refute_includes response.body, '--mui-primary'
    end
  end

  def test_logo_is_used_when_valid_and_ignored_when_not
    with_plugin_settings('logo_data' => PIXEL) do
      get :login
      assert_includes response.body, PIXEL
    end
    with_plugin_settings('logo_data' => 'data:text/html;base64,PHNjcmlwdD4=') do
      get :login
      refute_includes response.body, 'PHNjcmlwdD4='
    end
  end
end

# Other pages are not touched.
class ModernLoginPageScopeTest < Redmine::ControllerTest
  include ModernUiTestHelpers
  tests WelcomeController
  fixtures(*FIXTURES)

  def test_other_pages_do_not_load_it
    log_in 2
    get :index
    assert_response :success
    refute_match ModernLoginPageTest::STYLE, response.body
  end
end
