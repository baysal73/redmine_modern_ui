# frozen_string_literal: true

module ModernUi
  module Api
    # Reference data the UI needs to render filters and badges.
    class MetaController < BaseController
      def show
        projects = Project.visible.active.sorted.includes(:trackers).to_a
        render json: {
          user: { id: User.current.id, name: User.current.name, admin: User.current.admin?,
                  language: current_language.to_s },
          statuses: IssueStatus.sorted.map { |s| serializers.status(s) },
          trackers: Tracker.sorted.map { |t| serializers.ref(t) },
          priorities: IssuePriority.active.map { |p| serializers.ref(p).merge(is_default: p.is_default?) },
          addable_project_ids: Project.allowed_to(User.current, :add_issues).where(id: projects.map(&:id)).pluck(:id),
          projects: projects.map { |p| serializers.project(p) },
          settings: { per_page_options: Setting.per_page_options_array, text_formatting: Setting.text_formatting }
        }
      end
    end
  end
end
