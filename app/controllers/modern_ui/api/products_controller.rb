# frozen_string_literal: true

module ModernUi
  module Api
    # Products of the RedmineUP Products plugin (redmine_products). Reads use Product.visible (:view_products per project),
    # writes go through the plugin's safe_attributes and its own permission methods (editable_by?, destroyable_by?,
    # :add_products). Bundle members and the picture stay classic-only. Without the plugin every action answers 404.
    class ProductsController < BaseController
      include RedmineModernUi::SavedFilters
      before_action :require_products

      DEFAULT_PER_PAGE = 50
      MAX_PER_PAGE = 100
      EDITABLE = %i[name code status_id category_id currency price description tag_list].freeze
      CREATABLE = %i[name code status_id category_id currency price description].freeze
      ORDERS = {
        'name' => 'products.name', 'code' => 'products.code', 'price' => 'products.price', 'updated_at' => 'products.updated_at'
      }.freeze

      # GET /app/api/products
      #   q (name, code, description), status (all|1|2), category_id, project_id, bundle=1, sort, page, per_page
      def index
        scope = apply_free_filters(filtered(Product.visible))
        return render_json_error(422, @filter_error) unless scope

        per_page = (params[:per_page].presence || DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
        page = [params[:page].to_i, 1].max
        total = scope.count
        rows = scope.includes(:category, :project, :image).order(Arel.sql(order_sql)).offset((page - 1) * per_page).limit(per_page).to_a
        render json: { products: rows.map { |p| row(p) }, total: total, page: page, per_page: per_page, pages: (total.to_f / per_page).ceil }
      end

      # GET /app/api/products/options
      def options
        render json: {
          can_add: addable_projects.any?, projects: addable_projects.map { |p| { id: p.id, identifier: p.identifier, name: p.name } },
          categories: categories, statuses: statuses, currencies: ContactsSetting.major_currencies,
          default_currency: ContactsSetting.default_currency.to_s, default_status_id: Product::INACTIVE_PRODUCT
        }
      end

      # GET /app/api/products/:id
      def show
        render json: { product: detail(Product.visible.find(params[:id])) }
      end

      # POST /app/api/products { product: { project_id, name, code, status_id, category_id, currency, price, description } }
      def create
        attrs = params.require(:product).permit(*CREATABLE, :project_id).to_h
        project = find_visible_project(attrs.delete('project_id'))
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:add_products, project)

        attrs['price'] = decimal(attrs['price']) if attrs.key?('price')
        product = Product.new
        product.safe_attributes = attrs.compact_blank
        product.project = project
        product.author = User.current
        if product.save
          render json: { product: detail(Product.find(product.id)) }, status: :created
        else
          render_product_errors(product)
        end
      end

      # PATCH /app/api/products/:id
      def update
        product = Product.visible.find(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless product.editable_by?(User.current)

        attrs = params.require(:product).permit(*EDITABLE).to_h
        attrs['price'] = decimal(attrs['price']) if attrs.key?('price')
        attrs['code'] = attrs['code'].presence if attrs.key?('code') # the plugin wants unique codes or nil, never ''
        product.safe_attributes = attrs
        if product.save
          render json: { product: detail(Product.find(product.id)) }
        else
          render_product_errors(product)
        end
      end

      # DELETE /app/api/products/:id - not for products that sit on orders or invoices lines (the plugin would leave dangling lines)
      def destroy
        product = Product.visible.find(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless product.destroyable_by?(User.current)
        return render_json_error(422, l(:modern_ui_error_product_used)) if ProductLine.where(product_id: product.id).exists?

        if product.destroy
          head :no_content
        else
          render_json_error(422, product.errors.full_messages.to_sentence.presence || l(:modern_ui_error_forbidden))
        end
      end

      # POST /app/api/products/bulk { ids: [], op: 'status'|'delete', status_id: 1|2 }
      def bulk
        ids = Array(params[:ids]).map(&:to_i).uniq.first(100)
        op = params[:op].to_s
        return render_json_error(422, l(:modern_ui_error_bulk_op)) unless %w[status delete].include?(op)
        return render_json_error(422, l(:modern_ui_error_bulk_status)) if op == 'status' && ![1, 2].include?(params[:status_id].to_i)

        done = 0
        failed = []
        Product.visible.where(id: ids).each do |product|
          err = op == 'delete' ? bulk_delete_error(product) : bulk_status_error(product, params[:status_id].to_i)
          err ? failed << { id: product.id, name: product.name, error: err } : done += 1
        end
        render json: { done: done, failed: failed }
      end

      private

      def filter_query_class = ProductQuery
      def filter_model = Product
      def save_permission = :save_products_queries

      def bulk_delete_error(product)
        return l(:modern_ui_error_forbidden) unless product.destroyable_by?(User.current)
        return l(:modern_ui_error_product_used) if ProductLine.where(product_id: product.id).exists?

        product.destroy ? nil : (product.errors.full_messages.to_sentence.presence || l(:modern_ui_error_forbidden))
      end

      def bulk_status_error(product, status_id)
        return l(:modern_ui_error_forbidden) unless product.editable_by?(User.current)

        product.safe_attributes = { 'status_id' => status_id }
        product.save ? nil : product.errors.full_messages.to_sentence
      end

      def require_products
        render_json_error(404, l(:modern_ui_error_not_found)) unless defined?(::Product) && defined?(::ProductCategory)
      end

      def addable_projects
        @addable_projects ||= Project.visible.active.sorted.select { |p| User.current.allowed_to?(:add_products, p) }
      end

      def decimal(value)
        value.to_s.strip.tr(',', '.')
      end

      def render_product_errors(product)
        render json: { error: product.errors.full_messages.to_sentence, errors: product.errors.full_messages }, status: 422
      end

      def statuses
        [[Product::ACTIVE_PRODUCT, l(:label_products_status_active)], [Product::INACTIVE_PRODUCT, l(:label_products_status_inactive)]]
          .map { |id, name| { id: id, name: name } }
      end

      def categories
        ProductCategory.all.sort_by(&:lft).map { |c| { id: c.id, name: c.self_and_ancestors.map(&:name).join(' › ') } }
      end

      def filtered(scope)
        scope = scope.live_search(params[:q].to_s.strip) if params[:q].present?
        scope = scope.where(status_id: params[:status].to_i) if %w[1 2].include?(params[:status].to_s)
        scope = scope.where(category_id: ProductCategory.self_and_descendant_ids(params[:category_id])) if params[:category_id].present?
        scope = scope.where(project_id: find_visible_project(params[:project_id]).id) if params[:project_id].present?
        scope = scope.where(bundle: true) if params[:bundle].present?
        scope
      end

      def order_sql
        col, dir = params[:sort].to_s.split(':')
        "#{ORDERS[col] || ORDERS['name']} #{dir == 'desc' ? 'DESC' : 'ASC'}, products.id ASC"
      end

      def image_url(p)
        a = p.image
        a && "#{Redmine::Utils.relative_url_root}/attachments/download/#{a.id}/#{ERB::Util.url_encode(a.filename)}"
      end

      def row(p)
        {
          id: p.id, code: p.code.to_s, name: p.name, status: { id: p.status_id, name: p.status }, category: p.category&.to_s&.gsub('&#187;', '›'),
          price: p.price&.to_f, currency: p.currency.to_s, project: p.project.name, bundle: !!p.bundle, image_url: image_url(p), updated_at: p.updated_at
        }
      end

      def detail(p)
        user = User.current
        row(p).merge(
          project_identifier: p.project.identifier, description: p.description.to_s, category_id: p.category_id,
          tag_list: p.tag_list.to_a, created_at: p.created_at, author: serializers.user_ref(p.author),
          can_edit: !!p.editable_by?(user), can_delete: !!p.destroyable_by?(user), used: ProductLine.where(product_id: p.id).exists?,
          bundle_items: p.bundle? ? p.visible_bundle_items(user).map { |i| { id: i.product_id, name: i.product.name, quantity: i.quantity.to_f } } : []
        )
      end
    end
  end
end
