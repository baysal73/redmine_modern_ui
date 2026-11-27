# frozen_string_literal: true

module RedmineModernUi
  # Free filters and the user's private saved filters for a list screen, built on Redmine's own Query classes
  # (IssueQuery, and the ones of the CRM plugins: ContactQuery, InvoiceQuery, ProductQuery).
  #
  # The including controller provides
  #   filter_query_class   the Query subclass
  #   filter_model         the record class the list shows (Contact, Invoice, Product)
  #   save_permission      permission needed to save a query (e.g. :save_contacts_queries)
  # and may override +filter_project+ (the project the query is scoped to, default none).
  module SavedFilters
    # GET .../filters - every filter the query class offers with the operators allowed for its type. Remote filters (long
    # value lists) come without values; the browser asks for them with filter_values when the filter is opened.
    def filters
      query = new_filter_query
      list = query.available_filters_as_json.filter_map do |name, f|
        type = f['type'].to_s
        ops = Query.operators_by_filter_type[type.to_sym]
        next if ops.blank?

        { name: name, label: f['name'].to_s, type: type, remote: f['remote'] ? true : false,
          operators: ops.map { |o| { id: o, label: l(Query.operators[o]) } },
          values: f['values'] ? option_pairs(f['values']) : nil }
      end
      render json: { filters: list }
    end

    # GET .../filter_values?name=
    def filter_values
      filter = new_filter_query.available_filters[params[:name].to_s]
      render json: { values: filter ? option_pairs(filter.values) : [] }
    end

    # GET .../queries - the saved filters of the current user (Redmine's own saved queries, so they also show up in the
    # classic list)
    def queries
      list = filter_query_class.where(user_id: User.current.id).order(:name).map { |q| query_json(q) }
      render json: { queries: list, can_save: can_save_query? }
    end

    # POST .../queries { name, filters, state }  - state is the list screen's own state (JSON), kept so that applying the
    # view restores it exactly; the free filters are also stored as real Redmine filters
    def create_query
      name = params[:name].to_s.strip
      return render_json_error(422, l(:modern_ui_error_query_name)) if name.empty?
      return render_json_error(403, l(:modern_ui_error_forbidden)) unless can_save_query?

      query = new_filter_query
      free_filters(query).each { |f| query.add_filter(f['field'], f['op'], f['values']) }
      query.name = name[0, 255]
      query.user = User.current
      query.visibility = filter_query_class::VISIBILITY_PRIVATE
      state = saved_state
      query.options = (query.options || {}).merge('modern_state' => state) if state
      if query.save
        render json: { query: query_json(query) }, status: :created
      else
        render_json_error(422, query.errors.full_messages.to_sentence)
      end
    end

    # DELETE .../queries/:id - only the user's own
    def destroy_query
      query = filter_query_class.find_by(id: params[:id], user_id: User.current.id)
      return render_json_error(404, l(:modern_ui_error_not_found)) unless query

      query.destroy
      head :no_content
    end

    private

    def filter_project = nil

    def new_filter_query
      filter_query_class.new(name: '_', project: filter_project)
    end

    def can_save_query?
      User.current.allowed_to?(save_permission, filter_project, global: filter_project.nil?)
    end

    # Narrow a list scope with the free filters of the request (params[:filters]); nil when the filters are invalid
    def apply_free_filters(scope)
      list = free_filters(new_filter_query)
      return scope if list.empty?

      query = new_filter_query
      list.each { |f| query.add_filter(f['field'], f['op'], f['values']) }
      unless query.valid?
        @filter_error = query.errors.full_messages.to_sentence
        return nil
      end

      ids = query.objects_scope.reorder(nil).select("#{filter_model.table_name}.id")
      scope.where(id: ids)
    end

    # [[label, value], ...] for the filter pickers (values may be plain strings or one-element pairs)
    def option_pairs(values)
      Array(values).map do |v|
        v = Array(v)
        { label: v[0].to_s, value: (v[1] || v[0]).to_s }
      end
    end

    # Free filters from the filter dialog: JSON [{ field, op, values }]. Only fields this query offers and operators
    # allowed for the field's type are accepted; everything else is dropped.
    def free_filters(query)
      raw = params[:filters].presence
      return [] unless raw

      list = raw.is_a?(String) ? (JSON.parse(raw) rescue []) : []
      return [] unless list.is_a?(Array)

      available = query.available_filters
      list.first(40).filter_map do |f|
        next unless f.is_a?(Hash)

        field = f['field'].to_s
        op = f['op'].to_s
        filter = available[field]
        next unless filter && Query.operators_by_filter_type[filter[:type].to_sym].to_a.include?(op)

        { 'field' => field, 'op' => op, 'values' => Array(f['values']).map { |v| v.to_s[0, 255] }.first(200) }
      end
    end

    def saved_state
      raw = params[:state].presence
      h = raw.is_a?(String) ? (JSON.parse(raw) rescue nil) : nil
      return nil unless h.is_a?(Hash)

      h.first(30).to_h { |k, v| [k.to_s[0, 40], v.to_s[0, 4000]] }
    end

    def query_json(q)
      { id: q.id, name: q.name, project: q.project&.identifier, state: query_state(q) }
    end

    # Applying a saved view: the stored list state, or - for queries made in the classic UI - all its filters as free ones
    def query_state(q)
      stored = (q.options || {})['modern_state']
      return stored if stored.is_a?(Hash)

      free = q.filters.map { |field, cfg| { 'field' => field, 'op' => cfg[:operator].to_s, 'values' => Array(cfg[:values]).map(&:to_s) } }
      free.empty? ? {} : { 'filters' => free.to_json }
    end
  end
end
