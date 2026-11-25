# frozen_string_literal: true

# Serves the single-page app shell and a minimal JSON API.
# Plain (non-.json) URLs are used on purpose: Redmine ignores the browser session for
# *.json / *.xml requests (API-key only), so session auth + CSRF would not work there.
class ModernUiController < ApplicationController
  layout false
  before_action :require_login
  skip_before_action :check_if_login_required, only: [], raise: false

  def index
    @config = {
      base: "#{Redmine::Utils.relative_url_root}/#{RedmineModernUi.base_path}",
      root: Redmine::Utils.relative_url_root.to_s,
      lang: current_language.to_s,
      csrf: form_authenticity_token,
      brand: RedmineModernUi.brand
    }
    render :index, formats: :html
  end

  # The uploaded company logo, decoded from the plugin setting.
  def logo
    data = RedmineModernUi.logo_data
    return head(:not_found) unless data

    head_part, body = data.split(',', 2)
    type = head_part[/data:(.+?);/, 1]
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "default-src 'none'; style-src 'unsafe-inline'; sandbox"
    expires_in 1.day, public: false
    send_data Base64.strict_decode64(body), type: type, disposition: 'inline'
  rescue ArgumentError
    head :not_found
  end

  def me
    u = User.current
    render json: {
      id: u.id, login: u.login, name: u.name, admin: u.admin?, language: u.language.presence || Setting.default_language,
      classic_url: "#{Redmine::Utils.relative_url_root}/my/page"
    }
  end
end
