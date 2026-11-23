# frozen_string_literal: true

module ModernUi
  module Api
    # Data for the start page "My week": what is overdue, due soon, assigned to me and recently touched.
    class HomeController < BaseController
      LIMIT = 8

      def show
        today = User.current.today
        mine = { 'assigned_to_id' => ['=', ['me']] }
        overdue = fetch(mine.merge('status_id' => ['o', ['']], 'due_date' => ['<=', [(today - 1).to_s]]), 'due_date:asc')
        soon = fetch(mine.merge('status_id' => ['o', ['']], 'due_date' => ['><', [today.to_s, (today + 7).to_s]]), 'due_date:asc')
        undated = fetch(mine.merge('status_id' => ['o', ['']], 'due_date' => ['!*', ['']]), 'priority:desc,updated_on:desc')
        involved = Issue.visible.where('issues.assigned_to_id = :id OR issues.author_id = :id', id: User.current.id)
                        .includes(:status, :priority, :tracker, :author, :assigned_to, :project)
                        .order(updated_on: :desc).limit(LIMIT)
        render json: {
          today: today,
          overdue: rows(overdue), due_soon: rows(soon), undated: rows(undated),
          counts: { overdue: overdue[:total], due_soon: soon[:total], undated: undated[:total],
                    assigned_open: fetch(mine.merge('status_id' => ['o', ['']]), 'id:asc', 1)[:total] },
          recent: involved.map { |i| serializers.issue_row(i) }
        }
      end

      private

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
