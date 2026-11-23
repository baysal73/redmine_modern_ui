# frozen_string_literal: true

module ModernUi
  module Api
    class IssuesController < BaseController
      MAX_PER_PAGE = 100
      DEFAULT_PER_PAGE = 50
      # whitelist of sortable columns (name => IssueQuery column)
      SORTABLE = %w[id subject project tracker status priority author assigned_to start_date due_date
                    done_ratio created_on updated_on closed_on].freeze

      # GET /app/api/issues
      #   project_id    id or identifier (default: all visible projects)
      #   status        open (default) | closed | all | comma separated status ids
      #   tracker_id, priority_id, assigned_to_id, author_id   comma separated ids; assigned_to_id also "me" / "none"
      #   q             subject / description contains
      #   sort          e.g. "updated_on:desc,id:asc"
      #   page, per_page
      def index
        query = build_query
        per_page = per_page_param
        page = [params[:page].to_i, 1].max
        total = query.issue_count
        issues = query.issues(include: %i[status priority tracker author assigned_to project],
                              offset: (page - 1) * per_page, limit: per_page)
        render json: {
          issues: issues.map { |i| serializers.issue_row(i) },
          total: total, page: page, per_page: per_page, pages: (total.to_f / per_page).ceil
        }
      end

      # GET /app/api/issues/:id
      def show
        issue = Issue.visible.includes(:attachments, :project, :tracker, :status).find(params[:id])
        render json: { issue: serializers.issue_detail(issue, User.current, view_context) }
      end

      private

      def build_query
        project = params[:project_id].present? ? find_visible_project(params[:project_id]) : nil
        query = IssueQuery.new(name: '_', project: project)
        query.build_from_params(filter_params)
        query.sort_criteria = sort_criteria
        query
      end

      def ids(value)
        value.to_s.split(',').map(&:strip).reject(&:blank?)
      end

      def filter_params
        f = []
        op = {}
        v = {}
        add = lambda do |field, operator, values = ['']|
          f << field
          op[field] = operator
          v[field] = values
        end

        case params[:status].presence || 'open'
        when 'open'   then add.('status_id', 'o')
        when 'closed' then add.('status_id', 'c')
        when 'all'    then add.('status_id', '*')
        else add.('status_id', '=', ids(params[:status]))
        end
        add.('tracker_id', '=', ids(params[:tracker_id])) if params[:tracker_id].present?
        add.('priority_id', '=', ids(params[:priority_id])) if params[:priority_id].present?
        add.('author_id', '=', ids(params[:author_id])) if params[:author_id].present?
        if params[:assigned_to_id].present?
          if params[:assigned_to_id] == 'none'
            add.('assigned_to_id', '!*')
          else
            add.('assigned_to_id', '=', ids(params[:assigned_to_id]))
          end
        end
        add.('subject', '~', [params[:q].to_s]) if params[:q].present?
        { set_filter: '1', f: f, op: op, v: v }
      end

      def sort_criteria
        crit = ids(params[:sort]).filter_map do |part|
          col, dir = part.split(':')
          next unless SORTABLE.include?(col)

          [col, dir == 'asc' ? 'asc' : 'desc']
        end
        crit.presence || [%w[updated_on desc]]
      end

      def per_page_param
        n = params[:per_page].to_i
        n = DEFAULT_PER_PAGE if n <= 0
        [n, MAX_PER_PAGE].min
      end
    end
  end
end
