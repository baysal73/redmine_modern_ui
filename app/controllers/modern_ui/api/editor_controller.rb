# frozen_string_literal: true

module ModernUi
  module Api
    # GET /app/api/editor[?project_id=]
    # When Redmine's text formatting is CKEditor (plugin redmine_ckeditor) the new UI reuses that very editor, so
    # descriptions and comments are written and stored exactly as in the classic UI. This only hands the browser the
    # pieces the plugin's own helper would have put into the page; nothing is rendered here.
    class EditorController < BaseController
      def show
        return render json: { kind: 'plain' } unless ckeditor?

        project = params[:project_id].present? ? find_visible_project(params[:project_id]) : nil
        root = RedmineCkeditor.assets_root
        render json: {
          kind: 'ckeditor',
          basepath: "#{root}/ckeditor/",
          script: "#{root}/javascripts/application.js",
          plugins: RedmineCkeditor.plugins.map { |name| { name: name, path: "#{root}/ckeditor-contrib/plugins/#{name}/" } },
          options: RedmineCkeditor.options(project),
          mentions: mentions_config(project)
        }
      end

      private

      def ckeditor?
        defined?(RedmineCkeditor) && RedmineCkeditor.respond_to?(:enabled?) && RedmineCkeditor.enabled?
      end

      # Mention (@user / #issue) settings of the plugin; optional, so a failure only switches mentions off.
      def mentions_config(project)
        h = view_context
        list = []
        list << h.send(:user_mentions_options, project) if RedmineCkeditorSetting.user_mentions
        list << h.send(:issue_mentions_options, project) if RedmineCkeditorSetting.issue_mentions
        list
      rescue StandardError => e
        Rails.logger.warn("redmine_modern_ui: CKEditor mentions unavailable: #{e.class}")
        []
      end
    end
  end
end
