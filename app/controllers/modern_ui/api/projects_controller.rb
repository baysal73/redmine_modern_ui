# frozen_string_literal: true

module ModernUi
  module Api
    class ProjectsController < BaseController
      def index
        projects = Project.visible.active.sorted.includes(:trackers)
        render json: { projects: projects.map { |p| serializers.project(p) } }
      end

      # What the quick-create form offers for a project (only if the user may add issues there)
      def new_issue_options
        project = find_visible_project(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:add_issues, project)

        render json: {
          trackers: Issue.allowed_target_trackers(project, User.current).map { |t| serializers.ref(t) },
          priorities: IssuePriority.active.map { |p| serializers.ref(p).merge(is_default: p.is_default?) },
          assignees: project.assignable_users.map { |u| serializers.user_ref(u) }
        }
      end

      # Members that can be assigned (for filters / later: inline editing)
      def assignees
        project = find_visible_project(params[:id])
        users = project.assignable_users
        render json: { users: users.map { |u| serializers.user_ref(u) } }
      end
    end
  end
end
