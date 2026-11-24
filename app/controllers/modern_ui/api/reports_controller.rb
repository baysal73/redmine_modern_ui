# frozen_string_literal: true

module ModernUi
  module Api
    # Bridge to the Redmine Reporter plugin (RedmineUP). The SPA only lists the templates the user may use; generating,
    # previewing and sending is done by the plugin's own pages, so templates, prompts and permissions stay in one place.
    class ReportsController < BaseController
      # GET /app/api/report_templates[?issue_id=ID | ?project_id=ID]
      # -> { available, can_preview, can_generate, templates: [{ id, name, description }] }
      def templates
        return render json: { available: false, templates: [] } unless reporter?

        issue = params[:issue_id].present? ? Issue.visible.find(params[:issue_id]) : nil
        project = issue&.project || (params[:project_id].present? ? find_visible_project(params[:project_id]) : nil)
        user = User.current
        can_preview = user.allowed_to?(:view_issue_reports, project, global: project.nil?)
        can_generate = user.allowed_to?(:generate_issue_reports, project, global: project.nil?)
        list = can_preview || can_generate ? scope_for(issue, project).sorted.to_a : []
        render json: {
          available: true, can_preview: can_preview, can_generate: can_generate,
          templates: list.map { |t| { id: t.id, name: t.name, description: t.description.to_s } }
        }
      end

      private

      def reporter?
        defined?(::ReportTemplate) && defined?(::IssueReportTemplate)
      end

      # same choice as the plugin: one issue -> issue templates, otherwise templates for issue lists
      def scope_for(issue, project)
        base = issue ? ::IssueReportTemplate : ::ReportTemplate
        base.issue_templates.in_project_and_global(project)
      end
    end
  end
end
