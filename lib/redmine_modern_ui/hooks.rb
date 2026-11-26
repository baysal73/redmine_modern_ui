# frozen_string_literal: true

module RedmineModernUi
  class Hooks < Redmine::Hook::ViewListener
    # Opt-out checkbox on "My account"
    render_on :view_my_account, partial: 'hooks/modern_ui_my_account'

    LOGIN_ACTIONS = %w[login lost_password register].freeze

    # Modern look for the sign-in pages: one stylesheet, the brand colours and the logo as CSS variables.
    def view_layouts_base_html_head(context = {})
      controller = context[:controller]
      return '' unless RedmineModernUi.modern_login? && controller.is_a?(AccountController) && LOGIN_ACTIONS.include?(controller.action_name)

      view = context[:controller].view_context
      vars = { '--mui-primary' => RedmineModernUi.brand_color('brand_primary'), '--mui-gold' => RedmineModernUi.brand_color('brand_gold') }.compact
      css = +"body.controller-account{#{vars.map { |k, v| "#{k}:#{v}" }.join(';')}}"
      logo = RedmineModernUi.logo_data
      css << "body.controller-account #header h1::before{background:url(\"#{logo}\") center/contain no-repeat;box-shadow:none;width:auto;height:64px;border-radius:0}" if logo
      view.stylesheet_link_tag('login', plugin: 'redmine_modern_ui', media: 'all') +
        view.content_tag(:style, css.html_safe) # rubocop:disable Rails/OutputSafety -- colours and logo are validated in RedmineModernUi
    end
  end

  # Remember who just logged in so AccountControllerPatch can choose the landing page.
  class ControllerHooks < Redmine::Hook::Listener
    def controller_account_success_authentication_after(context = {})
      controller = context[:controller]
      controller.modern_ui_login_user = context[:user] if controller.respond_to?(:modern_ui_login_user=)
    end
  end
end
