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
      csrf: form_authenticity_token
    }
    render :index, formats: :html
  end

  def me
    u = User.current
    render json: {
      id: u.id, login: u.login, name: u.name, admin: u.admin?, language: u.language.presence || Setting.default_language,
      classic_url: "#{Redmine::Utils.relative_url_root}/my/page"
    }
  end
end
