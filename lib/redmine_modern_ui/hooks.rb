# frozen_string_literal: true

module RedmineModernUi
  class Hooks < Redmine::Hook::ViewListener
    # Opt-out checkbox on "My account"
    render_on :view_my_account, partial: 'hooks/modern_ui_my_account'
  end

  # Remember who just logged in so AccountControllerPatch can choose the landing page.
  class ControllerHooks < Redmine::Hook::Listener
    def controller_account_success_authentication_after(context = {})
      controller = context[:controller]
      controller.modern_ui_login_user = context[:user] if controller.respond_to?(:modern_ui_login_user=)
    end
  end
end
