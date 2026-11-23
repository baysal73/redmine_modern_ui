# frozen_string_literal: true

module RedmineModernUi
  # Turns Redmine models into plain hashes for the JSON API.
  # Only data the current user may see must be passed in (callers use visible scopes).
  module Serializers
    module_function

    # Defense in depth: Redmine's formatter output is sanitized, but formatter plugins (e.g. CKEditor) may let
    # tags such as <iframe> through. Everything that reaches the browser via v-html is cleaned once more with
    # Redmine's own HTML sanitizer (same allow-list as Markdown), falling back to Rails' safe-list sanitizer.
    FALLBACK_TAGS = (Rails::HTML5::SafeListSanitizer.allowed_tags.to_a + %w[table thead tbody tfoot tr th td caption]).freeze
    FALLBACK_ATTRIBUTES = (Rails::HTML5::SafeListSanitizer.allowed_attributes.to_a + %w[colspan rowspan]).freeze

    def safe_html(html)
      return '' if html.blank?

      if defined?(Redmine::WikiFormatting::HtmlSanitizer)
        Redmine::WikiFormatting::HtmlSanitizer.call(html.to_s)
      else
        ActionController::Base.helpers.sanitize(html.to_s, tags: FALLBACK_TAGS, attributes: FALLBACK_ATTRIBUTES)
      end
    end

    def user_ref(u)
      u && { id: u.id, name: u.name }
    end

    def ref(o)
      o && { id: o.id, name: o.name }
    end

    def status(s)
      { id: s.id, name: s.name, is_closed: s.is_closed? }
    end

    def project(p)
      { id: p.id, identifier: p.identifier, name: p.name, parent_id: p.parent_id,
        trackers: p.trackers.map { |t| ref(t) } }
    end

    def issue_row(i)
      {
        id: i.id, subject: i.subject,
        project: { id: i.project_id, name: i.project.name },
        tracker: ref(i.tracker), status: status(i.status), priority: ref(i.priority),
        author: user_ref(i.author), assigned_to: user_ref(i.assigned_to),
        start_date: i.start_date, due_date: i.due_date, done_ratio: i.done_ratio,
        created_on: i.created_on, updated_on: i.updated_on, closed_on: i.closed_on,
        is_private: i.is_private?
      }
    end

    # view: ActionView context (for textilizable and URLs)
    def issue_detail(i, user, view)
      issue_row(i).merge(
        description_html: i.description.present? ? safe_html(view.textilizable(i, :description)) : '',
        parent_id: i.parent_id,
        fixed_version: ref(i.fixed_version),
        category: ref(i.category),
        estimated_hours: i.estimated_hours,
        allowed_statuses: i.new_statuses_allowed_to(user, true).map { |s| status(s) },
        permissions: {
          edit: user.allowed_to?(:edit_issues, i.project) || i.attributes_editable?(user),
          comment: user.allowed_to?(:add_issue_notes, i.project),
          private_notes: user.allowed_to?(:set_notes_private, i.project),
          delete: user.allowed_to?(:delete_issues, i.project)
        },
        custom_fields: i.visible_custom_field_values(user).filter_map do |cv|
          next if cv.value.blank?

          # show_value handles multiple values and every field format (users, versions, lists, ...) as plain text
          { id: cv.custom_field.id, name: cv.custom_field.name, value: view.show_value(cv, false).to_s }
        end,
        attachments: i.attachments.map { |a| attachment(a) },
        journals: i.visible_journals_with_index(user).map { |j| journal(j, view) }
      )
    end

    SELECT_FORMATS = %w[list user version enumeration bool key_value].freeze
    SUPPORTED_FORMATS = (SELECT_FORMATS + %w[string text link int float date]).freeze

    # Definition of one custom field for the edit form (nil for formats the UI cannot edit, e.g. attachments)
    def custom_field_form(cv, issue)
      cf = cv.custom_field
      return nil unless SUPPORTED_FORMATS.include?(cf.field_format)

      kind = SELECT_FORMATS.include?(cf.field_format) ? 'select' : cf.field_format
      {
        id: cf.id, name: cf.name, format: cf.field_format, kind: kind, multiple: cf.multiple?, required: cf.is_required?,
        description: cf.description.to_s, value: cf.multiple? ? Array.wrap(cv.value).map(&:to_s) : cv.value.to_s,
        options: kind == 'select' ? cf.possible_values_options(issue).map { |label, value| { label: label.to_s, value: (value || label).to_s } } : []
      }
    end

    def attachment(a)
      { id: a.id, filename: a.filename, filesize: a.filesize, content_type: a.content_type,
        author: user_ref(a.author), created_on: a.created_on, description: a.description }
    end

    def journal(j, view)
      {
        id: j.id, index: j.indice, user: user_ref(j.user), created_on: j.created_on,
        private_notes: j.private_notes?,
        notes_html: j.notes.present? ? safe_html(view.textilizable(j, :notes)) : '',
        # plain-text sentence built by Redmine itself, e.g. "Status changed from New to Closed"
        details: j.visible_details.map { |d| { property: d.property, name: d.prop_key, text: view.show_detail(d, true) } }
      }
    end
  end
end
