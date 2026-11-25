# frozen_string_literal: true

module ModernUi
  module Api
    # RedmineUP Invoices plugin (redmine_contacts_invoices). Reads use Invoice.visible (:view_invoices per project).
    # Writes go through the plugin's own models exactly like its controllers do (safe_attributes, nested lines,
    # InvoicePayment with its Finance hooks), so totals, balance/status and bookkeeping entries are computed by the
    # plugin, never by this code. Every change checks the plugin's permissions and a version token (409 if the
    # invoice changed since the client loaded it). Number, contact, project and currency stay classic-only.
    class InvoicesController < BaseController
      before_action :require_invoices

      EDITABLE = %i[subject invoice_date due_date description order_number status_id assigned_to_id].freeze
      LINE_FIELDS = %i[id description quantity price tax discount units _destroy].freeze
      DEFAULT_PER_PAGE = 50
      MAX_PER_PAGE = 100
      ORDERS = {
        'invoice_date' => 'invoices.invoice_date', 'number' => 'invoices.number', 'due_date' => 'invoices.due_date',
        'amount' => 'invoices.amount', 'status' => 'invoices.status_id', 'balance' => 'invoices.balance'
      }.freeze

      # GET /app/api/invoices
      #   q (number, subject, contact), status (open | all | 0..4), project_id, contact_id, overdue=1, sort, page, per_page
      def index
        scope = filtered(Invoice.visible)
        per_page = (params[:per_page].presence || DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
        page = [params[:page].to_i, 1].max
        total = scope.count
        rows = scope.includes(:contact).order(Arel.sql(order_sql)).offset((page - 1) * per_page).limit(per_page).to_a
        render json: {
          invoices: rows.map { |i| row(i) }, total: total, page: page, per_page: per_page, pages: (total.to_f / per_page).ceil,
          sums: sums(scope)
        }
      end

      # GET /app/api/invoices/options
      def options
        render json: {
          statuses: Invoice.available_statuses.map { |id, name| { id: id, name: name } },
          projects: Project.visible.active.sorted.select { |p| User.current.allowed_to?(:view_invoices, p) }.map { |p| { id: p.id, identifier: p.identifier, name: p.name } },
          addable_projects: Project.visible.active.sorted.select { |p| User.current.allowed_to?(:add_invoices, p) }.map { |p| { id: p.id, identifier: p.identifier, name: p.name } }
        }
      end

      # GET /app/api/invoices/new?project_id=ID - suggested values for the create form (number from the plugin's number format)
      def new_defaults
        project = addable_project(params[:project_id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless project

        draft = Invoice.new(project: project)
        render json: {
          number: Invoice.generate_invoice_number(draft).to_s, invoice_date: User.current.today, currency: ContactsSetting.default_currency.to_s,
          currencies: ContactsSetting.major_currencies, tax: ContactsSetting.default_tax.to_f,
          statuses: Invoice.available_statuses.map { |id, name| { id: id, name: name } },
          assignees: project.assignable_users.map { |u| serializers.user_ref(u) }, assigned_to_id: User.current.id
        }
      end

      # POST /app/api/invoices { invoice: { project_id, contact_id, number, subject, invoice_date, due_date, currency, description,
      #                                     order_number, status_id, assigned_to_id, discount, lines: [...] } }
      def create
        raw = params.require(:invoice)
        project = addable_project(raw[:project_id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless project

        contact_id = raw[:contact_id].presence && raw[:contact_id].to_i
        return render_json_error(422, l(:modern_ui_error_invoice_contact)) if contact_id && !Contact.visible.exists?(contact_id)

        invoice = Invoice.new
        attrs = raw.permit(*EDITABLE, :number, :currency).to_h
        attrs['discount'] = raw[:discount].to_s.tr(',', '.').to_f if raw.key?(:discount)
        attrs['contact_id'] = contact_id
        attrs['project_id'] = project.id
        attrs['lines_attributes'] = new_lines(raw[:lines]) if raw[:lines].is_a?(Array)
        invoice.safe_attributes = attrs
        invoice.project = project
        invoice.author = User.current
        invoice.status_id ||= Invoice::DRAFT_INVOICE
        invoice.number = Invoice.apply_invoice_macros(invoice.number.presence || Invoice.generate_invoice_number(invoice), invoice)
        invoice.subject = Invoice.apply_invoice_macros(invoice.subject, invoice)
        invoice.assigned_to_id = nil unless invoice.assigned_to_id.nil? || project.assignable_users.map(&:id).include?(invoice.assigned_to_id)
        saved = false
        Invoice.transaction do
          saved = invoice.save && invoice.lines.reload.each(&:save)
          raise ActiveRecord::Rollback unless saved
        end
        return render_invoice_errors(invoice) unless saved

        render json: { invoice: detail(Invoice.find(invoice.id)) }, status: :created
      end

      # GET /app/api/invoices/:id
      def show
        render json: { invoice: detail(Invoice.visible.find(params[:id])) }
      end

      # GET /app/api/invoices/:id/form - choices for editing (only for users who may edit or record payments)
      def form
        invoice = Invoice.visible.find(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless invoice.editable_by?(User.current) || can_pay?(invoice)

        render json: {
          statuses: Invoice.available_statuses.map { |id, name| { id: id, name: name } },
          assignees: invoice.project.assignable_users.map { |u| serializers.user_ref(u) },
          finance: finance_options(invoice)
        }
      end

      # PATCH /app/api/invoices/:id
      #   { invoice: { subject, invoice_date, due_date, description, order_number, status_id, discount, assigned_to_id,
      #                lines: [{ id?, description, quantity, price, tax, discount, units, _destroy }], lock } }
      def update
        invoice = Invoice.visible.find(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless invoice.editable_by?(User.current)
        return render_json_error(409, l(:modern_ui_error_invoice_changed)) if stale?(invoice, params.dig(:invoice, :lock))

        raw = params.require(:invoice)
        attrs = raw.permit(*EDITABLE).to_h
        attrs['discount'] = raw[:discount].to_s.tr(',', '.').to_f if raw.key?(:discount)
        attrs['lines_attributes'] = lines_attributes(invoice, raw[:lines]) if raw[:lines].is_a?(Array)
        saved = false
        Invoice.transaction do
          invoice.safe_attributes = attrs
          saved = invoice.save && invoice.lines.reload.each(&:save)
          raise ActiveRecord::Rollback unless saved
        end
        return render_invoice_errors(invoice) unless saved

        render json: { invoice: detail(Invoice.find(invoice.id)) }
      rescue ActiveRecord::RecordNotFound
        render_json_error(422, l(:modern_ui_error_invoice_line))
      end

      # DELETE /app/api/invoices/:id - the plugin's own rule (destroyable_by?: :delete_invoices, or author with :edit_own_invoices)
      def destroy
        invoice = Invoice.visible.find(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless invoice.destroyable_by?(User.current)

        if invoice.destroy
          head :no_content
        else
          render_json_error(422, invoice.errors.full_messages.to_sentence.presence || l(:modern_ui_error_forbidden))
        end
      end

      # POST /app/api/invoices/:id/payments { payment: { amount, payment_date, description, account_id, category_id, lock } }
      def add_payment
        invoice = Invoice.visible.find(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless can_pay?(invoice)
        return render_json_error(409, l(:modern_ui_error_invoice_changed)) if stale?(invoice, params.dig(:payment, :lock))

        pp = params.require(:payment).permit(:amount, :payment_date, :description, :account_id, :category_id)
        amount = pp[:amount].to_s.tr(',', '.')
        return render_json_error(422, l(:modern_ui_error_payment_amount)) unless amount.match?(/\A\d+(\.\d+)?\z/) && amount.to_d.positive?

        payment = InvoicePayment.new
        payment.safe_attributes = pp.to_h.except('account_id', 'category_id').merge('amount' => amount)
        payment.safe_attributes = pp.to_h.slice('account_id', 'category_id') if finance_for?(invoice)
        payment.invoice = invoice
        payment.author = User.current
        if payment.save
          render json: { invoice: detail(Invoice.find(invoice.id)) }, status: :created
        else
          render json: { error: payment.errors.full_messages.to_sentence }, status: 422
        end
      end

      # DELETE /app/api/invoices/:id/payments/:payment_id
      def remove_payment
        invoice = Invoice.visible.find(params[:id])
        payment = invoice.payments.find(params[:payment_id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless payment.can_be_destroyed?
        return render_json_error(409, l(:modern_ui_error_invoice_changed)) if stale?(invoice, params[:lock])

        if payment.destroy
          render json: { invoice: detail(Invoice.find(invoice.id)) }
        else
          render json: { error: payment.errors.full_messages.to_sentence }, status: 422
        end
      end

      private

      def addable_project(id)
        project = Project.visible.active.find_by(id: id.to_s.to_i)
        project if project && User.current.allowed_to?(:add_invoices, project)
      end

      def new_lines(raw)
        raw.first(200).each_with_index.filter_map do |l, i|
          next unless l.respond_to?(:permit)

          a = l.permit(*(LINE_FIELDS - %i[id _destroy])).to_h
          a['position'] = i + 1
          a
        end
      end

      def can_pay?(invoice)
        User.current.allowed_to?(:edit_invoice_payments, invoice.project)
      end

      # Changes whatever the money fields depend on, so a client working on an old copy is turned away
      def version(invoice)
        Digest::MD5.hexdigest([invoice.updated_at.to_f, invoice.lines.maximum(:updated_at).to_f, invoice.lines.count,
                               invoice.payments.count, invoice.payments.sum(:amount).to_f, invoice.amount.to_f].join('|'))
      end

      def stale?(invoice, lock)
        lock.present? && lock.to_s != version(invoice)
      end

      def lines_attributes(invoice, raw)
        known = invoice.lines.pluck(:id)
        position = invoice.lines.maximum(:position).to_i
        raw.first(200).filter_map do |l|
          next unless l.respond_to?(:permit)

          a = l.permit(*LINE_FIELDS).to_h
          a['id'] = a['id'].to_i if a['id'].present?
          raise ActiveRecord::RecordNotFound if a['id'].present? && known.exclude?(a['id'])

          a['_destroy'] = a['_destroy'].to_s == 'true' ? '1' : nil
          a.compact!
          a['position'] = (position += 1) if a['id'].blank?
          a
        end
      end

      def render_invoice_errors(invoice)
        render json: { error: invoice.errors.full_messages.to_sentence, errors: invoice.errors.full_messages }, status: 422
      end

      def finance_for?(invoice)
        InvoicesSettings.finance_plugin_installed? && User.current.allowed_to?(:add_operations, invoice.project)
      end

      def finance_options(invoice)
        return { enabled: false, accounts: [], categories: [] } unless finance_for?(invoice) && defined?(::OperationCategory)

        { enabled: invoice.compatible_accounts.any? && OperationCategory.any?,
          accounts: invoice.compatible_accounts.map { |a| { id: a.id, name: a.name } },
          categories: OperationCategory.order(:name).map { |c| { id: c.id, name: c.name } } }
      end

      def require_invoices
        render_json_error(404, l(:modern_ui_error_not_found)) unless defined?(::Invoice) && defined?(::InvoiceLine)
      end

      def filtered(scope)
        scope = scope.left_joins(:contact).live_search_with_contact(params[:q].to_s.strip) if params[:q].present?
        case params[:status].presence || 'open'
        when 'open' then scope = scope.open
        when 'all' then nil
        else scope = scope.where(status_id: params[:status].to_s.split(',').map(&:to_i))
        end
        scope = scope.where(project_id: find_visible_project(params[:project_id]).id) if params[:project_id].present?
        scope = scope.where(contact_id: params[:contact_id].to_i) if params[:contact_id].present?
        scope = scope.where(status_id: Invoice::SENT_INVOICE).where('invoices.due_date <= ?', User.current.today) if params[:overdue].present?
        scope
      end

      def order_sql
        col, dir = params[:sort].to_s.split(':')
        sql = ORDERS[col] || ORDERS['invoice_date']
        direction = dir == 'asc' ? 'ASC' : 'DESC'
        "#{sql} #{direction}, invoices.id DESC"
      end

      # per currency: what is invoiced and what is still unpaid, for everything the filters match (not just this page)
      def sums(scope)
        base = scope.reorder(nil)
        amount = base.group(:currency).sum(:amount)
        paid = base.group(:currency).sum(:balance)
        amount.map { |cur, a| { currency: cur.to_s, amount: a.to_f, open: (a.to_f - paid[cur].to_f).round(2) } }
      end

      def status(i)
        { id: i.status_id, name: i.status }
      end

      def row(i)
        {
          id: i.id, number: i.number, subject: i.subject.to_s, invoice_date: i.invoice_date&.to_date, due_date: i.due_date&.to_date,
          status: status(i), currency: i.currency.to_s, amount: i.amount.to_f, balance: i.balance.to_f,
          remaining: (i.amount.to_f - i.balance.to_f).round(2), overdue: !!i.overdue?,
          contact: i.contact && { id: i.contact_id, name: i.contact.name }, project: i.project.name
        }
      end

      def detail(i)
        user = User.current
        row(i).merge(
          project_identifier: i.project.identifier, description: i.description.to_s, order_number: i.order_number.to_s,
          paid_date: i.paid_date&.to_date, discount: i.discount, assigned_to: serializers.user_ref(i.assigned_to), assigned_to_id: i.assigned_to_id, author: serializers.user_ref(i.author),
          contact_visible: i.contact ? Contact.visible.exists?(i.contact_id) : false,
          can_edit: !!i.editable_by?(user), can_delete: !!i.destroyable_by?(user), lock: version(i), can_pay: user.allowed_to?(:edit_invoice_payments, i.project),
          subtotal: i.subtotal, tax_amount: i.tax_amount, discount_amount: i.discount_amount,
          lines: i.lines.map { |l| { id: l.id, description: l.description.to_s, quantity: l.quantity.to_f, units: l.units.to_s, price: l.price.to_f, tax: l.tax&.to_f, discount: l.discount&.to_f, total: l.total.to_f } },
          payments: i.payments.map { |p| { id: p.id, date: p.payment_date&.to_date, amount: p.amount.to_f, description: p.description.to_s, can_remove: !!p.can_be_destroyed?(user) } }
        )
      end
    end
  end
end
