# frozen_string_literal: true

module RedmineModernUi
  # After a successful login, go to the new UI instead of the default landing page -
  # unless a back_url was given (deep links keep working) or the user opted out.
  #
  # The login is detected through Redmine's own hook (controller_account_success_authentication_after, see hooks.rb)
  # instead of wrapping AccountController#successful_authentication. That keeps this plugin compatible with other
  # plugins that replace the default landing page (they only change the default argument of redirect_back_or_default,
  # which we override here when the new UI is enabled).
  module AccountControllerPatch
    attr_writer :modern_ui_login_user

    private

    def redirect_back_or_default(default, options = {})
      if @modern_ui_login_user && RedmineModernUi.redirect_after_login?(@modern_ui_login_user)
        default = modern_ui_path
      end
      super(default, options)
    end
  end
end
