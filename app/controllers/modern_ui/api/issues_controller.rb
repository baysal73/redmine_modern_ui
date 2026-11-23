# frozen_string_literal: true

module ModernUi
  module Api
    class IssuesController < BaseController
      helper :issues, :custom_fields, :attachments
      MAX_PER_PAGE = 100
      DEFAULT_PER_PAGE = 50
      BOARD_DEFAULT_LIMIT = 30
      CREATABLE_FIELDS = %i[project_id tracker_id subject description assigned_to_id priority_id due_date start_date].freeze
      EDITABLE_FIELDS = %i[status_id assigned_to_id priority_id due_date start_date done_ratio subject description category_id
                           fixed_version_id estimated_hours is_private notes private_notes].freeze
      # whitelist of sortable columns (name => IssueQuery column)
      SORTABLE = %w[id subject project tracker status priority author assigned_to start_date due_date
                    done_ratio created_on updated_on closed_on].freeze

      # GET /app/api/issues
      #   project_id    id or identifier (default: all visible projects)
      #   status        open (default) | closed | all | comma separated status ids
      #   tracker_id, priority_id, assigned_to_id, author_id   comma separated ids; assigned_to_id also "me" / "none"
      #   due           overdue | week | none
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

      # GET /app/api/issues/board - one column per status, same filters as the list
      # (project_id, tracker_id, priority_id, assigned_to_id, author_id, q). Each card carries the
      # status ids the current user may move it to (Redmine workflow), so the UI can offer only valid drops.
      def board
        limit = [params[:limit].to_i, 1].max.clamp(1, MAX_PER_PAGE)
        limit = BOARD_DEFAULT_LIMIT if params[:limit].blank?
        allowed_cache = {}
        columns = IssueStatus.sorted.map do |status|
          # closed columns: most recently touched first (old closed issues are rarely interesting)
          query = build_query(status: status.id.to_s, sort: status.is_closed? ? 'updated_on:desc' : 'priority:desc,updated_on:desc')
          issues = query.issues(include: %i[status priority tracker author assigned_to project], limit: limit)
          cards = issues.map do |i|
            key = [i.project_id, i.tracker_id, i.status_id, i.author_id == User.current.id, i.assigned_to_id == User.current.id,
                   i.attributes_editable?(User.current)]
            allowed = allowed_cache[key] ||= (key.last ? i.new_statuses_allowed_to(User.current, true).map(&:id) : [])
            serializers.issue_row(i).merge(allowed_status_ids: allowed)
          end
          { status: serializers.status(status), total: query.issue_count, issues: cards }
        end
        render json: { columns: columns, limit: limit }
      end

      # GET /app/api/issues/:id
      def show
        issue = Issue.visible.includes(:attachments, :project, :tracker, :status).find(params[:id])
        render json: { issue: serializers.issue_detail(issue, User.current, view_context) }
      end

      # GET /app/api/issues/:id/options - what the current user may choose when editing (workflow aware)
      def options
        issue = Issue.visible.find(params[:id])
        render json: {
          allowed_statuses: issue.new_statuses_allowed_to(User.current, true).map { |s| serializers.status(s) },
          assignees: issue.assignable_users.map { |u| serializers.user_ref(u) },
          priorities: IssuePriority.active.map { |p| serializers.ref(p) },
          editable: issue.attributes_editable?(User.current)
        }
      end

      # GET /app/api/issues/:id/form - everything the full edit dialog needs: current values, which fields this user may
      # change (Redmine's safe_attribute_names, i.e. role + workflow aware), required fields, choices and custom fields.
      def form
        issue = Issue.visible.includes(:project).find(params[:id])
        user = User.current
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless issue.attributes_editable?(user)

        names = issue.safe_attribute_names(user)
        editable = EDITABLE_FIELDS.map(&:to_s) & names
        read_only = issue.read_only_attribute_names(user)
        render json: {
          values: {
            subject: issue.subject, description: issue.description.to_s, status_id: issue.status_id, priority_id: issue.priority_id,
            assigned_to_id: issue.assigned_to_id, category_id: issue.category_id, fixed_version_id: issue.fixed_version_id,
            start_date: issue.start_date, due_date: issue.due_date, done_ratio: issue.done_ratio,
            estimated_hours: issue.estimated_hours, is_private: issue.is_private?
          },
          editable: (editable - read_only).uniq,
          required: %w[subject status_id priority_id assigned_to_id category_id fixed_version_id start_date due_date done_ratio
                       estimated_hours description].select { |n| issue.required_attribute?(n, user) },
          description_as_text: %w[textile common_mark markdown].include?(Setting.text_formatting.to_s),
          options: {
            statuses: issue.new_statuses_allowed_to(user, true).map { |st| serializers.status(st) },
            priorities: IssuePriority.active.map { |pr| serializers.ref(pr) },
            assignees: issue.assignable_users.map { |u| serializers.user_ref(u) },
            categories: issue.project.issue_categories.map { |c| serializers.ref(c) },
            versions: issue.assignable_versions.map { |v| serializers.ref(v) }
          },
          custom_fields: issue.editable_custom_field_values(user).filter_map { |cv| serializers.custom_field_form(cv, issue) }
        }
      end

      # POST /app/api/issues  { issue: { project_id, tracker_id, subject, description, assigned_to_id, priority_id, due_date } }
      # Same checks as the classic form (add_issues permission, allowed trackers, safe_attributes). Projects that require
      # custom fields are answered with 422 plus a link to the classic form, which can render those fields.
      def create
        attrs = params.require(:issue).permit(*CREATABLE_FIELDS).to_h
        project = find_visible_project(attrs['project_id'])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:add_issues, project)

        trackers = Issue.allowed_target_trackers(project, User.current)
        tracker = trackers.find { |t| t.id.to_s == attrs['tracker_id'].to_s } || trackers.first
        return render_json_error(422, l(:modern_ui_error_no_tracker)) unless tracker

        issue = Issue.new(project: project, tracker: tracker, author: User.current)
        issue.start_date ||= User.current.today if Setting.default_issue_start_date_to_creation_date?
        issue.safe_attributes = attrs.except('project_id', 'tracker_id')
        if issue.save
          render json: { issue: serializers.issue_row(issue.reload) }, status: :created
        else
          render json: { error: issue.errors.full_messages.to_sentence, errors: issue.errors.full_messages,
                         classic_url: "#{Redmine::Utils.relative_url_root}/projects/#{project.identifier}/issues/new?issue[tracker_id]=#{tracker.id}" },
                 status: 422
        end
      end

      # PATCH /app/api/issues/:id  { issue: { status_id, assigned_to_id, priority_id, due_date, notes } }
      # Uses Redmine's safe_attributes, so field permissions and workflow rules apply exactly as in the classic UI.
      def update
        issue = Issue.visible.find(params[:id])
        attrs = params.require(:issue).permit(*EDITABLE_FIELDS).to_h
        private_notes = attrs.delete('private_notes').to_s == 'true'
        if params[:issue][:custom_field_values].respond_to?(:to_unsafe_h)
          # {custom_field_id => value or [values]}; Redmine's safe_attributes drops fields the user may not edit
          attrs['custom_field_values'] = params[:issue][:custom_field_values].to_unsafe_h
                                                                              .transform_values { |v| v.is_a?(Array) ? v.map(&:to_s) : v.to_s }
        end
        if attrs.keys == %w[notes]
          return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:add_issue_notes, issue.project)
          return render_json_error(422, l(:modern_ui_error_notes_blank)) if attrs['notes'].to_s.strip.empty?
        elsif !issue.attributes_editable?(User.current)
          return render_json_error(403, l(:modern_ui_error_forbidden))
        end

        if attrs.key?('status_id') && attrs['status_id'].to_s != issue.status_id.to_s &&
           issue.new_statuses_allowed_to(User.current).map(&:id).exclude?(attrs['status_id'].to_i)
          return render_json_error(422, l(:modern_ui_error_status_not_allowed))
        end

        notes = attrs.delete('notes')
        notes = nil unless User.current.allowed_to?(:add_issue_notes, issue.project)
        journal = issue.init_journal(User.current, notes)
        if notes.present? && private_notes && User.current.allowed_to?(:set_notes_private, issue.project)
          journal.private_notes = true
        end
        issue.safe_attributes = attrs
        if issue.save
          render json: { issue: serializers.issue_row(issue.reload) }
        else
          render json: { error: issue.errors.full_messages.to_sentence, errors: issue.errors.full_messages }, status: 422
        end
      end

      private

      def build_query(status: nil, sort: nil)
        project = params[:project_id].present? ? find_visible_project(params[:project_id]) : nil
        query = IssueQuery.new(name: '_', project: project)
        query.build_from_params(filter_params(status))
        query.sort_criteria = sort_criteria(sort)
        query
      end

      def ids(value)
        value.to_s.split(',').map(&:strip).reject(&:blank?)
      end

      def filter_params(status_override = nil)
        f = []
        op = {}
        v = {}
        add = lambda do |field, operator, values = ['']|
          f << field
          op[field] = operator
          v[field] = values
        end

        status = status_override || params[:status].presence || 'open'
        case status
        when 'open'   then add.('status_id', 'o')
        when 'closed' then add.('status_id', 'c')
        when 'all'    then add.('status_id', '*')
        else add.('status_id', '=', ids(status))
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
        today = User.current.today
        case params[:due]
        when 'overdue' then add.('due_date', '<=', [(today - 1).to_s]) && add.('status_id', 'o') # open issues only
        when 'week'    then add.('due_date', '><', [today.to_s, (today + 7).to_s])
        when 'none'    then add.('due_date', '!*')
        end
        add.('subject', '~', [params[:q].to_s]) if params[:q].present?
        { set_filter: '1', f: f, op: op, v: v }
      end

      def sort_criteria(override = nil)
        crit = ids(override || params[:sort]).filter_map do |part|
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
