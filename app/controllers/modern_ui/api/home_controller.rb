# frozen_string_literal: true

module ModernUi
  module Api
    # Data for the start page "My week": what is overdue, due soon, assigned to me and recently touched, and the
    # user's own dashboard layout (stored in the user preferences, so it follows the user to every device).
    class HomeController < BaseController
      LIMIT = 8
      WIDGET_TYPES = %w[stats overdue due_soon undated assigned reported watched recent query cal_day cal_week].freeze
      WIDGET_SIZES = %w[s m l full].freeze
      MAX_WIDGETS = 24
      PREF_KEY = :modern_ui_home

      def show
        today = User.current.today
        mine = { 'assigned_to_id' => ['=', ['me']] }
        overdue = fetch(mine.merge('status_id' => RedmineModernUi.open_status_filter, 'due_date' => ['<=', [(today - 1).to_s]]), 'due_date:asc')
        soon = fetch(mine.merge('status_id' => RedmineModernUi.open_status_filter, 'due_date' => ['><', [today.to_s, (today + 7).to_s]]), 'due_date:asc')
        undated = fetch(mine.merge('status_id' => RedmineModernUi.open_status_filter, 'due_date' => ['!*', ['']]), 'priority:desc,updated_on:desc')
        involved = Issue.visible.where('issues.assigned_to_id = :id OR issues.author_id = :id', id: User.current.id)
                        .includes(:status, :priority, :tracker, :author, :assigned_to, :project)
                        .order(updated_on: :desc).limit(LIMIT)
        render json: {
          today: today,
          overdue: rows(overdue), due_soon: rows(soon), undated: rows(undated),
          counts: { overdue: overdue[:total], due_soon: soon[:total], undated: undated[:total],
                    assigned_open: fetch(mine.merge('status_id' => RedmineModernUi.open_status_filter), 'id:asc', 1)[:total] },
          recent: involved.map { |i| serializers.issue_row(i) }
        }
      end

      # GET /app/api/home/layout: the user's dashboard widgets, or null for the default layout (built by the SPA)
      def layout
        render json: { widgets: User.current.pref[PREF_KEY].presence }
      end

      # PUT /app/api/home/layout {widgets: [{id, type, size, limit, query_id}]}
      def update_layout
        widgets = Array(params[:widgets]).first(MAX_WIDGETS).filter_map { |w| clean_widget(w) }
        store_layout(widgets)
        render json: { widgets: widgets }
      end

      # DELETE /app/api/home/layout: back to the default layout
      def reset_layout
        store_layout(nil)
        head :no_content
      end

      private

      def clean_widget(raw)
        return nil unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

        type = raw[:type].to_s
        return nil unless WIDGET_TYPES.include?(type)

        w = { 'id' => raw[:id].to_s[/\A[\w-]{1,32}\z/] || SecureRandom.hex(4), 'type' => type,
              'size' => WIDGET_SIZES.include?(raw[:size].to_s) ? raw[:size].to_s : 'm' }
        w['limit'] = raw[:limit].to_i.clamp(3, 25) if raw[:limit].present?
        if type == 'query'
          id = raw[:query_id].to_i
          return nil unless id.positive?

          w['query_id'] = id
        end
        w
      end

      def store_layout(widgets)
        pref = User.current.pref
        if widgets.nil?
          pref.others.delete(PREF_KEY)
        else
          pref[PREF_KEY] = widgets
        end
        pref.save!
      end

      def fetch(filters, sort, limit = LIMIT)
        query = IssueQuery.new(name: '_')
        query.build_from_params(set_filter: '1', f: filters.keys,
                                op: filters.transform_values(&:first), v: filters.transform_values(&:last))
        query.sort_criteria = sort.split(',').map { |s| s.split(':') }
        { total: query.issue_count,
          issues: query.issues(include: %i[status priority tracker author assigned_to project], limit: limit) }
      end

      def rows(result)
        result[:issues].map { |i| serializers.issue_row(i) }
      end
    end
  end
end
