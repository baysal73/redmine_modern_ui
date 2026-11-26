# frozen_string_literal: true

module RedmineModernUi
  # After a successful login, go to the new UI instead of the default landing page -
  # unless a back_url to a specific page was given (deep links keep working) or the user opted out.
  # A back_url to Redmine's generic landing pages (the start address, "My page") is no deep link: people who open
  # the plain address get sent to /login?back_url=/ and should still end up in the new UI.
  #
  # The login is detected through Redmine's own hook (controller_account_success_authentication_after, see hooks.rb)
  # instead of wrapping AccountController#successful_authentication. That keeps this plugin compatible with other
  # plugins that replace the default landing page (they only change the default argument of redirect_back_or_default,
  # which we override here when the new UI is enabled).
  module AccountControllerPatch
    attr_writer :modern_ui_login_user

    private

    GENERIC_LANDING_PATHS = ['', '/', '/home', '/my/page'].freeze

    def redirect_back_or_default(default, options = {})
      if @modern_ui_login_user && RedmineModernUi.redirect_after_login?(@modern_ui_login_user)
        default = modern_ui_path
        params.delete(:back_url) if generic_landing_url?(params[:back_url])
      end
      super(default, options)
    end

    def generic_landing_url?(url)
      return false if url.blank?

      path = URI.parse(url.to_s).path.to_s.chomp('/')
      root = Redmine::Utils.relative_url_root.to_s.chomp('/')
      path = path.delete_prefix(root) if root.present?
      GENERIC_LANDING_PATHS.include?(path.presence || '')
    rescue URI::InvalidURIError
      false
    end
  end
end
