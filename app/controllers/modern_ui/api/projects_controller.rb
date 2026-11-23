# frozen_string_literal: true

module ModernUi
  module Api
    class ProjectsController < BaseController
      def index
        projects = Project.visible.active.sorted.includes(:trackers)
        render json: { projects: projects.map { |p| serializers.project(p) } }
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
