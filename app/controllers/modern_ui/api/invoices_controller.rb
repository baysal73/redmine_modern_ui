# frozen_string_literal: true

module ModernUi
  module Api
    # Read-only view of the RedmineUP Invoices plugin (redmine_contacts_invoices).
    # Money is deliberately not editable here: payments, lines and statuses touch totals, balances and (with the
    # Finance plugin) bookkeeping entries, so creating or changing them stays in the plugin's own screens, which the
    # detail panel links to. Visibility is Invoice.visible, i.e. the plugin's :view_invoices permission per project.
    class InvoicesController < BaseController
      before_action :require_invoices

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
          projects: Project.visible.active.sorted.select { |p| User.current.allowed_to?(:view_invoices, p) }.map { |p| { id: p.id, identifier: p.identifier, name: p.name } }
        }
      end

      # GET /app/api/invoices/:id
      def show
        render json: { invoice: detail(Invoice.visible.find(params[:id])) }
      end

      private

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
          paid_date: i.paid_date&.to_date, discount: i.discount, assigned_to: serializers.user_ref(i.assigned_to), author: serializers.user_ref(i.author),
          contact_visible: i.contact ? Contact.visible.exists?(i.contact_id) : false,
          can_edit: !!i.editable_by?(user), can_pay: user.allowed_to?(:edit_invoice_payments, i.project),
          subtotal: i.subtotal, tax_amount: i.tax_amount, discount_amount: i.discount_amount,
          lines: i.lines.map { |l| { id: l.id, description: l.description.to_s, quantity: l.quantity.to_f, units: l.units.to_s, price: l.price.to_f, tax: l.tax&.to_f, discount: l.discount&.to_f, total: l.total.to_f } },
          payments: i.payments.map { |p| { id: p.id, date: p.payment_date&.to_date, amount: p.amount.to_f, description: p.description.to_s } }
        )
      end
    end
  end
end
