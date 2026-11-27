# frozen_string_literal: true

module ModernUi
  module Api
    class IssuesController < BaseController
      include RedmineModernUi::SavedFilters
      helper :issues, :custom_fields, :attachments
      MAX_PER_PAGE = 100
      DEFAULT_PER_PAGE = 50
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
        return render_json_error(422, query.errors.full_messages.to_sentence) unless query.valid?

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

      # GET /app/api/issues/queries - the saved filters of the current user (Redmine's own saved queries, so they also
      # show up in the classic ticket list)
      def queries
        user = User.current
        list = IssueQuery.where(user_id: user.id).includes(:project).order(:name).map do |q|
          { id: q.id, name: q.name, project: q.project&.identifier, state: query_state(q) }
        end
        render json: { queries: list, can_save: user.allowed_to?(:save_queries, nil, global: true) }
      end

      # POST /app/api/issues/queries { name, project_id?, + the same filter parameters as GET /issues }
      def create_query
        name = params[:name].to_s.strip
        return render_json_error(422, l(:modern_ui_error_query_name)) if name.empty?

        project = optional_project
        unless User.current.allowed_to?(:save_queries, project, global: project.nil?)
          return render_json_error(403, l(:modern_ui_error_forbidden))
        end

        query = build_query(for_save: true)
        query.name = name[0, 255]
        query.user = User.current
        query.visibility = IssueQuery::VISIBILITY_PRIVATE
        query.group_by = params[:group].to_s if IssueQuery.new.groupable_columns.map { |c| c.name.to_s }.include?(params[:group].to_s)
        if query.save
          render json: { query: { id: query.id, name: query.name, project: query.project&.identifier, state: query_state(query) } }, status: :created
        else
          render_json_error(422, query.errors.full_messages.to_sentence)
        end
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
          project_id: issue.project.identifier,
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
        issue.save_attachments(upload_params)
        if issue.save
          render json: { issue: serializers.issue_row(issue.reload) }, status: :created
        else
          render json: { error: issue.errors.full_messages.to_sentence, errors: issue.errors.full_messages,
                         classic_url: "#{Redmine::Utils.relative_url_root}/projects/#{project.identifier}/issues/new?issue[tracker_id]=#{tracker.id}" },
                 status: 422
        end
      end

      # DELETE /app/api/issues/:id[?with_subtasks=1] - needs :delete_issues. Issues with logged time stay classic-only (the classic view
      # asks what to do with the hours); subtasks are deleted by Redmine too, so the client must confirm them first (409 with the count).
      def destroy
        issue = Issue.visible.find(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:delete_issues, issue.project)

        hours = TimeEntry.where(issue_id: issue.self_and_descendants.select(:id)).count
        return render_json_error(422, l(:modern_ui_error_issue_has_time)) if hours.positive?

        subtasks = issue.descendants.count
        if subtasks.positive? && params[:with_subtasks].to_s != '1'
          return render json: { error: l(:modern_ui_error_issue_has_subtasks, count: subtasks), subtasks: subtasks }, status: 409
        end

        if issue.reload.destroy
          head :no_content
        else
          render_json_error(422, issue.errors.full_messages.to_sentence.presence || l(:modern_ui_error_forbidden))
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
        uploads = upload_params
        if (attrs.keys - %w[notes]).empty?
          return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:add_issue_notes, issue.project)
          return render_json_error(422, l(:modern_ui_error_notes_blank)) if attrs['notes'].to_s.strip.empty? && uploads.empty?
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
        issue.save_attachments(uploads) if uploads.any? && User.current.allowed_to?(:add_issue_notes, issue.project)
        if issue.save
          render json: { issue: serializers.issue_row(issue.reload) }
        else
          render json: { error: issue.errors.full_messages.to_sentence, errors: issue.errors.full_messages }, status: 422
        end
      end

      BULK_FIELDS = %i[status_id assigned_to_id priority_id due_date].freeze
      MAX_BULK = 100

      # POST /app/api/issues/bulk  { ids: [1, 2], issue: { status_id, assigned_to_id, priority_id, due_date } }
      # Every issue goes through the same checks as a single update (visibility, edit permission, workflow,
      # safe_attributes). Issues that fail are reported, the others are still saved.
      def bulk
        ids = Array(params[:ids]).map(&:to_i).uniq.first(MAX_BULK + 1)
        return render_json_error(422, l(:modern_ui_error_bulk_empty)) if ids.empty?
        return render_json_error(422, l(:modern_ui_error_bulk_too_many, max: MAX_BULK)) if ids.size > MAX_BULK

        attrs = params.require(:issue).permit(*BULK_FIELDS).to_h
        return render_json_error(422, l(:modern_ui_error_bulk_empty)) if attrs.empty?

        updated = []
        failed = []
        Issue.visible.where(id: ids).includes(:project, :status).each do |issue|
          error = bulk_update_error(issue, attrs)
          if error
            failed << { id: issue.id, error: error }
          else
            updated << serializers.issue_row(issue.reload)
          end
        end
        (ids - updated.map { |i| i[:id] } - failed.map { |f| f[:id] }).each do |id|
          failed << { id: id, error: l(:modern_ui_error_not_found) }
        end
        render json: { updated: updated, failed: failed }
      end

      private

      # [{ token:, filename: }] from issue[uploads]; Redmine matches them to the files stored by UploadsController
      def upload_params
        raw = params.dig(:issue, :uploads)
        return [] unless raw.is_a?(Array)

        raw.filter_map do |u|
          next unless u.respond_to?(:permit)

          u.permit(:token, :filename, :content_type, :description).to_h
        end.select { |u| own_upload?(u['token']) }.first(10)
      end

      # Only files the current user uploaded themselves can be attached (Redmine alone would accept any valid token)
      def own_upload?(token)
        a = token.present? ? Attachment.find_by_token(token) : nil
        a.present? && a.container_id.nil? && a.author_id == User.current.id
      end

      def bulk_update_error(issue, attrs)
        return l(:modern_ui_error_forbidden) unless issue.attributes_editable?(User.current)

        if attrs.key?('status_id') && attrs['status_id'].to_s != issue.status_id.to_s &&
           issue.new_statuses_allowed_to(User.current).map(&:id).exclude?(attrs['status_id'].to_i)
          return l(:modern_ui_error_status_not_allowed)
        end

        issue.init_journal(User.current)
        issue.safe_attributes = attrs
        issue.save ? nil : issue.errors.full_messages.to_sentence
      end

      def build_query(status: nil, sort: nil, for_save: false)
        project = optional_project
        query = IssueQuery.new(name: '_', project: project)
        query.build_from_params(filter_params(status, for_save: for_save))
        free_filters(query).each { |f| query.add_filter(f['field'], f['op'], f['values']) }
        query.sort_criteria = sort_criteria(sort)
        query
      end

      def optional_project
        params[:project_id].present? ? find_visible_project(params[:project_id]) : nil
      end

      def filter_query_class = IssueQuery
      def filter_project = optional_project
      def save_permission = :save_queries

      # The saved query as state for the list screen: the simple filters map to the quick chips, everything else stays a
      # free filter.
      def query_state(q)
        s = { 'status' => 'all', 'tracker' => '', 'priority' => '', 'assignee' => '', 'due' => '', 'q' => '' }
        free = []
        q.filters.each do |field, cfg|
          op = cfg[:operator].to_s
          vals = Array(cfg[:values]).map(&:to_s).reject(&:empty?)
          ok = case field
               when 'status_id'
                 st = { 'o' => 'open', 'c' => 'closed', '*' => 'all' }[op] || (op == '=' && vals.any? ? vals.join(',') : nil)
                 st && (s['status'] = st)
               when 'tracker_id' then op == '=' && vals.any? && (s['tracker'] = vals.join(','))
               when 'priority_id' then op == '=' && vals.any? && (s['priority'] = vals.join(','))
               when 'assigned_to_id'
                 if op == '!*' then s['assignee'] = 'none'
                 elsif op == '=' && vals.any? then s['assignee'] = vals.join(',')
                 end
               when 'subject' then op == '~' && vals.size == 1 && (s['q'] = vals.first)
               when 'due_date'
                 d = if op == '<t-' && vals == ['0'] then 'overdue'
                     elsif op == '><t+' && vals == ['7'] then 'week'
                     elsif op == '!*' then 'none'
                     end
                 d && (s['due'] = d)
               end
          free << { 'field' => field, 'op' => op, 'values' => Array(cfg[:values]).map(&:to_s) } unless ok
        end
        sort = q.sort_criteria.to_a.filter_map { |col, dir| "#{col}:#{dir}" if SORTABLE.include?(col.to_s) }.join(',')
        s['sort'] = sort.presence || 'updated_on:desc'
        s['group'] = %w[status priority assigned_to project tracker].include?(q.group_by.to_s) ? q.group_by.to_s : ''
        s['filters'] = free.empty? ? '' : free.to_json
        s['project'] = q.project&.identifier.to_s
        s
      end

      def ids(value)
        value.to_s.split(',').map(&:strip).reject(&:blank?)
      end

      def filter_params(status_override = nil, for_save: false)
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
        when 'open'   then add.('status_id', *RedmineModernUi.open_status_filter)
        when 'closed' then add.('status_id', *RedmineModernUi.closed_status_filter)
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
        # a saved filter must stay correct tomorrow, so it uses Redmine's relative operators instead of fixed dates
        when 'overdue'
          for_save ? add.('due_date', '<t-', ['0']) : add.('due_date', '<=', [(today - 1).to_s])
          add.('status_id', *RedmineModernUi.open_status_filter) # open issues only
        when 'week'    then for_save ? add.('due_date', '><t+', ['7']) : add.('due_date', '><', [today.to_s, (today + 7).to_s])
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
