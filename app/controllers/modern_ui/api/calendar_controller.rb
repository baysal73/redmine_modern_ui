# frozen_string_literal: true

module ModernUi
  module Api
    # Calendar on top of the events plugin plugin (calendar_events): events plus issues with dates. The plugin owns the data,
    # the permissions (CalendarPlugin::Access) and the Google Calendar sync; this controller only exposes them to the SPA.
    # Without the plugin every action answers 404.
    class CalendarController < BaseController
      before_action :require_calendar
      before_action :require_view
      before_action :require_manage, only: %i[create update destroy]
      before_action :require_admin_user, only: :sync
      before_action :find_event, only: %i[update destroy]

      MAX_RANGE_DAYS = 100

      # GET /app/api/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD[&q=&category=&mine=1]
      def index
        from = parse_date(params[:from]) || Date.current.beginning_of_month
        to = parse_date(params[:to]) || from + 41
        to = from + MAX_RANGE_DAYS if to > from + MAX_RANGE_DAYS
        q = params[:q].to_s.strip
        category = params[:category].to_s.presence
        mine = params[:mine] == '1'
        events = load_events(from, to, q, category, mine)
        issues = load_issues(from, to, q, category, mine)
        render json: {
          from: from.iso8601, to: to.iso8601, can_manage: manage?, time_zone: tz.name,
          google: google_state, categories: categories_json,
          events: events.map { |e| event_json(e) }, issues: issues.map { |i| issue_json(i) }
        }
      end

      # POST /app/api/calendar/events
      def create
        ev = CalendarEvent.new
        ev.author = User.current
        save(ev, status: :created)
      end

      # PATCH /app/api/calendar/events/:id
      def update
        save(@event)
      end

      # DELETE /app/api/calendar/events/:id
      def destroy
        @event.soft_delete!
        sync_soon
        head :no_content
      end

      # POST /app/api/calendar/sync (administrators): start the Google sync now
      def sync
        return render_json_error(422, l(:modern_ui_error_calendar_sync)) unless CalendarPlugin::Config.gcal_ready?

        CalendarPlugin::Syncer.run_async
        render json: { ok: true }
      end

      private

      def require_calendar
        render_json_error(404, l(:modern_ui_error_not_found)) unless defined?(::CalendarEvent) && defined?(::CalendarPlugin::Access)
      end

      def require_view
        deny_access unless CalendarPlugin::Access.can_view?(User.current)
      end

      def require_manage
        deny_access unless manage?
      end

      def require_admin_user
        deny_access unless User.current.admin?
      end

      def manage?
        CalendarPlugin::Access.can_manage?(User.current)
      end

      def find_event
        @event = CalendarEvent.find(params[:id])
      end

      def tz
        User.current.time_zone || ActiveSupport::TimeZone[CalendarPlugin::Config.time_zone] || ActiveSupport::TimeZone['Europe/Berlin']
      end

      def parse_date(value)
        Date.iso8601(value.to_s[0, 10])
      rescue ArgumentError
        nil
      end

      def sync_soon
        CalendarPlugin::Syncer.run_soon
      rescue StandardError => e
        Rails.logger.error("[modern_ui] calendar sync: #{e.message}")
      end

      def google_state
        { enabled: CalendarPlugin::Config.gcal_ready?, admin: User.current.admin? }
      end

      def categories_json
        CalendarPlugin::Config.categories.map { |c| { name: c[:name], color: c[:color] } }
      end

      def like(term)
        "%#{ActiveRecord::Base.sanitize_sql_like(term.downcase)}%"
      end

      def load_events(from, to, q, category, mine)
        lo = tz.local(from.year, from.month, from.day).utc
        hi = tz.local(to.year, to.month, to.day).utc + 1.day
        scope = CalendarEvent.between(lo, hi)
        scope = scope.where(category: category) if category
        scope = scope.where(author_id: User.current.id) if mine
        if q.present?
          t = like(q)
          scope = scope.where('LOWER(calendar_events.title) LIKE ? OR LOWER(calendar_events.location) LIKE ? OR LOWER(calendar_events.description) LIKE ?', t, t, t)
        end
        scope.includes(:project).order(:starts_at).limit(1000).to_a
      end

      def load_issues(from, to, q, category, mine)
        ids = CalendarPlugin::Config.tracker_ids
        return [] if ids.empty? || category

        scope = Issue.visible(User.current).where(tracker_id: ids)
                     .where('(issues.start_date IS NOT NULL AND issues.start_date <= ? AND COALESCE(issues.due_date, issues.start_date) >= ?) OR ' \
                            '(issues.start_date IS NULL AND issues.due_date BETWEEN ? AND ?)', to, from, from, to)
        scope = scope.joins(:status).where(issue_statuses: { is_closed: false }) unless CalendarPlugin::Config.flag?(:issue_include_closed)
        scope = scope.where(assigned_to_id: User.current.id) if mine
        scope = scope.where('LOWER(issues.subject) LIKE ?', like(q)) if q.present?
        scope.includes(:project, :tracker, :status, :assigned_to).order(:id).limit(1000).to_a
      end

      def event_json(ev)
        ev.as_api(tz).merge(
          color: ev.color, project: ev.project && { id: ev.project.id, name: ev.project.name },
          contact: contact_json(ev), google: ev.google_event_id.present?
        )
      end

      def contact_json(ev)
        c = ev.contact_id && defined?(::Contact) ? ::Contact.visible.find_by(id: ev.contact_id) : nil
        c && { id: c.id, name: c.name }
      end

      def issue_json(issue)
        {
          id: issue.id, subject: issue.subject, tracker: issue.tracker.name, status: issue.status.name,
          project: issue.project.name, start_date: issue.start_date&.iso8601, due_date: issue.due_date&.iso8601,
          assigned_to: issue.assigned_to&.name, color: CalendarPlugin::ISSUE_COLOR
        }
      end

      # Same field handling as the classic controller: flat JSON, all-day events stored as Google does it (UTC midnight, end exclusive).
      def save(ev, status: :ok)
        p = params.to_unsafe_h.with_indifferent_access
        return unprocessable(ev) unless assign(ev, p)

        if ev.save
          sync_soon
          render json: { event: event_json(ev) }, status: status
        else
          unprocessable(ev)
        end
      end

      def unprocessable(ev)
        render json: { error: ev.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end

      def assign(ev, p)
        ev.title = p[:title] if p.key?(:title)
        ev.description = p[:description] if p.key?(:description)
        ev.location = p[:location] if p.key?(:location)
        ev.category = p[:category].presence if p.key?(:category)
        return false unless assign_refs(ev, p)

        ev.all_day = ActiveModel::Type::Boolean.new.cast(p[:all_day]) if p.key?(:all_day)
        assign_times(ev, p)
      rescue ArgumentError
        ev.errors.add(:base, l(:label_calendar_event_invalid_time))
        false
      end

      def assign_refs(ev, p)
        if p.key?(:project_id)
          pid = p[:project_id].presence
          return invalid(ev, l(:modern_ui_error_not_found)) if pid && !Project.visible.exists?(id: pid)

          ev.project_id = pid
        end
        if p.key?(:contact_id)
          cid = p[:contact_id].presence
          return invalid(ev, l(:modern_ui_error_invoice_contact)) if cid && !(defined?(::Contact) && ::Contact.visible.exists?(id: cid))

          ev.contact_id = cid
        end
        true
      end

      def invalid(ev, message)
        ev.errors.add(:base, message)
        false
      end

      def assign_times(ev, p)
        if ev.all_day
          sd = p[:start_date].presence || p[:starts_at].presence
          return true unless sd

          s = Date.parse(sd.to_s[0, 10])
          ed = p[:end_date].presence || p[:ends_at].presence
          e = ed ? Date.parse(ed.to_s[0, 10]) : s
          e = s if e < s
          ev.starts_at = Time.utc(s.year, s.month, s.day)
          ev.ends_at = Time.utc(e.year, e.month, e.day) + 1.day
        else
          ev.starts_at = tz.parse(p[:starts_at].to_s).utc if p[:starts_at].present?
          ev.ends_at = tz.parse(p[:ends_at].to_s).utc if p[:ends_at].present?
        end
        true
      end
    end
  end
end
