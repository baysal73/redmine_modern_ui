# frozen_string_literal: true

module ModernUi
  module Api
    # Contacts of the RedmineUP CRM plugin (redmine_contacts). Everything goes through the plugin's own scopes and
    # permission checks (Contact.visible, #editable?, :add_contacts, :add_notes), so users only see and change what
    # they may in the classic UI. Without the plugin every action answers 404.
    class ContactsController < BaseController
      before_action :require_crm
      helper :custom_fields

      DEFAULT_PER_PAGE = 50
      MAX_PER_PAGE = 100
      EDITABLE = %i[first_name last_name middle_name company job_title website skype_name birthday background phone email
                    assigned_to_id visibility tag_list].freeze
      CREATABLE = %i[is_company first_name last_name company job_title email phone].freeze
      ADDRESS_FIELDS = %w[street1 street2 postcode city region country_code].freeze
      NOTE_TYPES = [nil, 0, 1, 2].freeze
      ORDERS = {
        'name' => 'contacts.first_name, contacts.last_name', 'company' => 'contacts.company, contacts.first_name',
        'updated_on' => 'contacts.updated_on', 'created_on' => 'contacts.created_on'
      }.freeze

      # GET /app/api/contacts
      #   q, kind (all|company|person), assigned_to_id (me|id), project_id, cf[ID]=value, sort (name|company|updated_on|created_on[:desc]), page, per_page
      def index
        scope = filtered(Contact.visible)
        per_page = (params[:per_page].presence || DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
        page = [params[:page].to_i, 1].max
        total = scope.count
        rows = scope.includes(:address, :assigned_to).order(Arel.sql(order_sql)).offset((page - 1) * per_page).limit(per_page).to_a
        render json: { contacts: rows.map { |c| row(c) }, total: total, page: page, per_page: per_page, pages: (total.to_f / per_page).ceil }
      end

      # GET /app/api/contacts/options - choices for the filters and the create dialog
      def options
        fields = ContactCustomField.where(field_format: 'list').sorted.select { |f| f.visible_by?(nil, User.current) rescue true }
        render json: {
          can_add: addable_projects.any?,
          projects: addable_projects.map { |p| { id: p.id, identifier: p.identifier, name: p.name } },
          custom_fields: fields.map { |f| { id: f.id, name: f.name, values: f.possible_values.map(&:to_s) } },
          assignees: User.visible.active.sorted.limit(500).map { |u| serializers.user_ref(u) }
        }
      end

      # GET /app/api/contacts/:id
      def show
        render json: { contact: detail(find_contact) }
      end

      # POST /app/api/contacts { contact: { first_name, last_name, company, is_company, email, phone, project_id } }
      def create
        attrs = params.require(:contact).permit(*CREATABLE, :project_id).to_h
        project = find_visible_project(attrs.delete('project_id'))
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:add_contacts, project)

        contact = Contact.new(author: User.current)
        contact.project = project
        contact.safe_attributes = attrs
        if contact.save
          render json: { contact: detail(Contact.find(contact.id)) }, status: :created
        else
          render json: { error: contact.errors.full_messages.to_sentence, errors: contact.errors.full_messages }, status: 422
        end
      end

      # PATCH /app/api/contacts/:id { contact: { ... , address: { city: .. }, custom_field_values: { id => value } } }
      def update
        contact = find_contact
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless contact.editable?

        attrs = params.require(:contact).permit(*EDITABLE).to_h
        if params[:contact][:custom_field_values].respond_to?(:to_unsafe_h)
          attrs['custom_field_values'] = params[:contact][:custom_field_values].to_unsafe_h
        end
        contact.safe_attributes = attrs
        apply_address(contact, params[:contact][:address])
        if contact.save
          render json: { contact: detail(Contact.find(contact.id)) }
        else
          render json: { error: contact.errors.full_messages.to_sentence, errors: contact.errors.full_messages }, status: 422
        end
      end

      # POST /app/api/contacts/:id/notes { note: { content, type_id, subject } }
      def add_note
        contact = find_contact
        unless contact.projects.any? { |p| User.current.allowed_to?(:add_notes, p) }
          return render_json_error(403, l(:modern_ui_error_forbidden))
        end

        np = params.require(:note).permit(:content, :type_id, :subject)
        note = Note.new
        note.safe_attributes = { 'content' => np[:content].to_s, 'subject' => np[:subject].to_s,
                                 'type_id' => NOTE_TYPES.include?(np[:type_id].presence&.to_i) ? np[:type_id].presence : nil }
        note.source = contact
        note.author = User.current
        if note.save
          render json: { note: note_json(note) }, status: :created
        else
          render json: { error: note.errors.full_messages.to_sentence }, status: 422
        end
      end

      # POST /app/api/contacts/bulk { ids: [], op: 'delete' } - only contacts the user may delete (plugin rule: deletable?)
      def bulk
        ids = Array(params[:ids]).map(&:to_i).uniq.first(100)
        return render_json_error(422, l(:modern_ui_error_bulk_op)) unless params[:op].to_s == 'delete'

        done = 0
        failed = []
        Contact.visible.where(id: ids).each do |contact|
          err = if !contact.deletable?(User.current) then l(:modern_ui_error_forbidden)
                elsif contact.destroy then nil
                else contact.errors.full_messages.to_sentence.presence || l(:modern_ui_error_forbidden)
                end
          err ? failed << { id: contact.id, name: contact.name, error: err } : done += 1
        end
        render json: { done: done, failed: failed }
      end

      private

      def require_crm
        render_json_error(404, l(:modern_ui_error_not_found)) unless defined?(::Contact) && defined?(::ContactNote)
      end

      def find_contact
        Contact.visible.find(params[:id])
      end

      def addable_projects
        @addable_projects ||= Project.visible.active.sorted.select { |p| User.current.allowed_to?(:add_contacts, p) }
      end

      def filtered(scope)
        scope = scope.live_search(params[:q].to_s.strip) if params[:q].present?
        scope = scope.where(is_company: true) if params[:kind] == 'company'
        scope = scope.where(is_company: false) if params[:kind] == 'person'
        if params[:assigned_to_id].present?
          id = params[:assigned_to_id] == 'me' ? User.current.id : params[:assigned_to_id].to_i
          scope = scope.where(assigned_to_id: id)
        end
        scope = scope.where(projects: { id: find_visible_project(params[:project_id]).id }) if params[:project_id].present?
        cf = params[:cf]
        if cf.respond_to?(:to_unsafe_h)
          cf.to_unsafe_h.first(5).each do |id, value|
            next if value.blank?

            ids = CustomValue.where(customized_type: 'Contact', custom_field_id: id.to_i, value: value.to_s).select(:customized_id)
            scope = scope.where(id: ids)
          end
        end
        scope
      end

      def order_sql
        col, dir = params[:sort].to_s.split(':')
        sql = ORDERS[col] || ORDERS['updated_on']
        col = 'updated_on' unless ORDERS.key?(col)
        direction = dir ? (dir == 'asc' ? 'ASC' : 'DESC') : (col.end_with?('_on') ? 'DESC' : 'ASC')
        sql.split(', ').map { |c| "#{c} #{direction}" }.join(', ') + ', contacts.id ASC'
      end

      def apply_address(contact, raw)
        return unless raw.respond_to?(:permit)

        attrs = raw.permit(*ADDRESS_FIELDS).to_h
        address = contact.address || contact.build_address(address_type: 'business')
        address.assign_attributes(attrs)
        address.save if contact.persisted? && (address.persisted? || !address.blank?)
      end

      def row(c)
        {
          id: c.id, name: c.name, is_company: c.is_company?, company: c.company.to_s, job_title: c.job_title.to_s,
          email: c.email.to_s, phone: c.phone.to_s, city: c.address&.city.to_s, assigned_to: serializers.user_ref(c.assigned_to),
          updated_on: c.updated_on
        }
      end

      def detail(c)
        user = User.current
        editable = c.editable?
        company = c.contact_company
        {
          id: c.id, name: c.name, is_company: c.is_company?, editable: editable,
          can_add_note: c.projects.any? { |p| user.allowed_to?(:add_notes, p) },
          project_id: c.projects.first&.identifier,
          projects: c.projects.map { |p| { id: p.id, identifier: p.identifier, name: p.name } },
          values: {
            first_name: c.first_name.to_s, last_name: c.last_name.to_s, middle_name: c.middle_name.to_s, company: c.company.to_s,
            job_title: c.job_title.to_s, website: c.website.to_s, skype_name: c.skype_name.to_s, birthday: c.birthday,
            background: c.background.to_s, phone: c.phone.to_s, email: c.email.to_s, assigned_to_id: c.assigned_to_id,
            visibility: c.visibility, tag_list: c.tag_list.to_a
          },
          address: ADDRESS_FIELDS.index_with { |f| c.address&.send(f).to_s },
          assignees: User.visible.active.sorted.limit(500).map { |u| serializers.user_ref(u) },
          assigned_to: serializers.user_ref(c.assigned_to), author: serializers.user_ref(c.author),
          background_html: c.background.present? ? serializers.safe_html(view_context.textilizable(c, :background)) : '',
          created_on: c.created_on, updated_on: c.updated_on,
          avatar_url: avatar_url(c),
          company_contact: company && Contact.visible.exists?(company.id) ? { id: company.id, name: company.name } : nil,
          employees: c.is_company? ? c.company_contacts.merge(Contact.visible).limit(100).map { |e| { id: e.id, name: e.name, job_title: e.job_title.to_s } } : [],
          custom_fields: c.custom_field_values.filter_map { |cv| serializers.custom_field_form(cv, nil, attachments: true) },
          deals: deals(c, user), issues: c.related_issues.includes(:status).order(updated_on: :desc).limit(50).map { |i| issue_ref(i) },
          timeline: timeline(c, user),
          notes: ContactNote.where(source_type: 'Contact', source_id: c.id).includes(:author).order(created_on: :desc).limit(100).map { |n| note_json(n) }
        }
      end

      TIMELINE_MAX = 80

      # Everything that happened around a contact in one list, newest first: notes, tickets, invoices and calendar events.
      # Each source respects its own visibility rules; the optional plugins (invoices, events) are only asked when installed.
      def timeline(c, user)
        out = []
        ContactNote.where(source_type: 'Contact', source_id: c.id).includes(:author).order(created_on: :desc).limit(40).each do |n|
          text = n.subject.presence || ActionController::Base.helpers.strip_tags(n.content.to_s).squish.truncate(90)
          out << { kind: 'note', id: n.id, date: n.created_on, title: text, meta: n.author&.name.to_s }
        end
        c.related_issues.includes(:status, :project).order(updated_on: :desc).limit(40).each do |i|
          out << { kind: 'issue', id: i.id, date: i.updated_on, title: "##{i.id} #{i.subject}", meta: "#{i.status.name} · #{i.project.name}" }
        end
        if defined?(::Invoice) && user.allowed_to_globally?(:view_invoices, {})
          Invoice.visible.where(contact_id: c.id).includes(:project).order(invoice_date: :desc).limit(40).each do |i|
            out << { kind: 'invoice', id: i.id, date: i.invoice_date&.to_time, day_only: true, title: i.number.to_s,
                     meta: "#{view_context.number_with_precision(i.amount.to_f, precision: 2)} #{i.currency} · #{Invoice.available_statuses[i.status_id]}" }
          end
        end
        calendar = RedmineModernUi::CalendarBackend.current
        if calendar && calendar.access.can_view?(user)
          calendar.event_class.where(contact_id: c.id).order(starts_at: :desc).limit(40).each do |e|
            out << { kind: 'event', id: e.id, date: e.starts_at, title: e.title, meta: e.location.to_s, day: e.starts_at.to_date.iso8601 }
          end
        end
        out.select { |x| x[:date] }.sort_by { |x| x[:date] }.reverse.first(TIMELINE_MAX).map { |x| x.merge(date: x[:date].iso8601) }
      end

      def avatar_url(c)
        a = c.avatar
        a && "#{Redmine::Utils.relative_url_root}/attachments/download/#{a.id}/#{ERB::Util.url_encode(a.filename)}"
      end

      def deals(c, user)
        c.all_visible_deals(user).first(50).map do |d|
          { id: d.id, name: d.name, status: d.status&.name, price: d.price, currency: d.currency, project: d.project&.name }
        end
      end

      def issue_ref(i)
        { id: i.id, subject: i.subject, status: serializers.status(i.status), project: i.project.name }
      end

      def note_json(n)
        {
          id: n.id, author: serializers.user_ref(n.author), created_on: n.created_on, type_id: n.type_id, subject: n.subject.to_s,
          content_html: serializers.safe_html(view_context.textilizable(n, :content))
        }
      end
    end
  end
end
