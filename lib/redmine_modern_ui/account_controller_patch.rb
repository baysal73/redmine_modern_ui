# frozen_string_literal: true

module RedmineModernUi
  # After a successful login, go to the new UI instead of "My page" -
  # unless a back_url was given (deep links keep working) or the user opted out.
  module AccountControllerPatch
    private

    def successful_authentication(user)
      @modern_ui_login_user = user
      super
    ensure
      @modern_ui_login_user = nil
    end

    def redirect_back_or_default(default, options = {})
      if @modern_ui_login_user && default == my_page_path &&
         RedmineModernUi.redirect_after_login?(@modern_ui_login_user)
        default = modern_ui_path
      end
      super(default, options)
    end
  end
end
