# frozen_string_literal: true

module RedmineModernUi
  # Finds an events plugin that can feed the calendar screen. Nothing is configured: a plugin qualifies when its
  # namespace (the camel-cased plugin id, e.g. "my_events" -> MyEvents) provides
  #
  #   Access.can_view?(user), Access.can_manage?(user)
  #   Config.gcal_ready?, .categories, .tracker_ids, .time_zone, .flag?(name)
  #   Syncer.run_async, Syncer.run_soon
  #   ISSUE_COLOR                       (optional, a CSS colour)
  #
  # and a model named like the singular namespace (MyEvent) with the scope +between(from, to)+ and the usual
  # columns (title, description, location, category, starts_at, ends_at, all_day, project_id, contact_id,
  # google_event_id) plus +as_api(time_zone)+, +color+ and +soft_delete!+.
  # Without such a plugin the calendar is off: the endpoints answer 404 and the menu entry is not shown.
  module CalendarBackend
    Backend = Struct.new(:plugin_id, :namespace, :event_class) do
      def access = namespace::Access
      def config = namespace::Config
      def syncer = namespace::Syncer
      def issue_color = namespace.const_defined?(:ISSUE_COLOR) ? namespace::ISSUE_COLOR : '#6366f1'
      def table = event_class.table_name
    end

    module_function

    # The backend for the current installation, or nil.
    def current
      Redmine::Plugin.all.each do |plugin|
        backend = from_namespace(plugin.id.to_s, plugin.id.to_s.camelize.safe_constantize)
        return backend if backend
      end
      nil
    end

    def from_namespace(plugin_id, namespace)
      return nil unless namespace.is_a?(Module)

      event_class = namespace.name.to_s.singularize.safe_constantize
      return nil unless event_class.is_a?(Class) && event_class.respond_to?(:between)
      return nil unless provides?(namespace, :Access, %i[can_view? can_manage?])
      return nil unless provides?(namespace, :Config, %i[gcal_ready? categories tracker_ids time_zone flag?])
      return nil unless provides?(namespace, :Syncer, %i[run_async run_soon])

      Backend.new(plugin_id, namespace, event_class)
    end

    def provides?(namespace, const, methods)
      return false unless namespace.const_defined?(const, false)

      target = namespace.const_get(const, false)
      methods.all? { |m| target.respond_to?(m) }
    end
  end
end
