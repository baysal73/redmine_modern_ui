# frozen_string_literal: true

module ModernUi
  module Api
    # Base for the JSON endpoints used by the SPA.
    # Authentication = normal Redmine session; writes need the CSRF token (X-CSRF-Token header).
    # Every query goes through Redmine's visibility scopes, so users only get what they may see.
    class BaseController < ApplicationController
      layout false
      before_action :require_login
      rescue_from ActiveRecord::RecordNotFound do
        render_json_error 404, l(:modern_ui_error_not_found)
      end

      private

      # Redmine's require_login would redirect to the login page; the SPA needs a 401.
      def require_login
        return true if User.current.logged?

        render_json_error 401, l(:modern_ui_error_login_required)
        false
      end

      # Redmine renders an HTML error page (and drops the session) on a bad CSRF token; the SPA needs JSON.
      def handle_unverified_request
        render_json_error 422, l(:modern_ui_error_csrf)
      end

      # Redmine's default handler redirects; the SPA needs JSON.
      def deny_access
        User.current.logged? ? render_json_error(403, l(:modern_ui_error_forbidden)) : require_login
      end

      def render_json_error(status, message)
        render json: { error: message }, status: status
      end

      # Visible project by numeric id or identifier; raises RecordNotFound otherwise.
      def find_visible_project(id)
        scope = Project.visible
        id.to_s.match?(/\A\d+\z/) ? scope.find(id) : scope.find_by!(identifier: id.to_s)
      end

      def serializers
        RedmineModernUi::Serializers
      end
    end
  end
end
