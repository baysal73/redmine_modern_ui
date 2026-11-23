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
          classic_menu: classic_menu,
          settings: { per_page_options: Setting.per_page_options_array, text_formatting: Setting.text_formatting }
        }
      end

      private

      # Links of Redmine's own global menus (including those added by other plugins, e.g. CRM), so the new UI can
      # point to everything it does not replace yet. Items we cover ourselves are left out.
      COVERED = %w[home my_page issues modern_ui].freeze

      def classic_menu
        helper = view_context
        %i[application_menu top_menu].flat_map do |menu|
          Redmine::MenuManager.items(menu).root.children.filter_map do |node|
            next if COVERED.include?(node.name.to_s)
            next unless node.allowed?(User.current, nil)

            caption, url, = helper.send(:extract_node_details, node, nil)
            url = helper.url_for(url) if url.is_a?(Hash)
            next if url.blank? || caption.blank?

            { name: node.name.to_s, caption: caption.to_s, url: url.to_s }
          rescue StandardError => e
            Rails.logger.warn("redmine_modern_ui: skipped menu item #{node.name}: #{e.class}")
            nil
          end
        end.uniq { |i| i[:name] }
      end
    end
  end
end
