# frozen_string_literal: true

module RedmineModernUi
  # Turns Redmine models into plain hashes for the JSON API.
  # Only data the current user may see must be passed in (callers use visible scopes).
  module Serializers
    module_function

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
        description_html: i.description.present? ? view.textilizable(i, :description) : '',
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

          { id: cv.custom_field.id, name: cv.custom_field.name,
            value: cv.custom_field.format.formatted_value(view, cv.custom_field, cv.value, i, false).to_s }
        end,
        attachments: i.attachments.map { |a| attachment(a) },
        journals: i.visible_journals_with_index(user).map { |j| journal(j, view) }
      )
    end

    def attachment(a)
      { id: a.id, filename: a.filename, filesize: a.filesize, content_type: a.content_type,
        author: user_ref(a.author), created_on: a.created_on, description: a.description }
    end

    def journal(j, view)
      {
        id: j.id, index: j.indice, user: user_ref(j.user), created_on: j.created_on,
        private_notes: j.private_notes?,
        notes_html: j.notes.present? ? view.textilizable(j, :notes) : '',
        # plain-text sentence built by Redmine itself, e.g. "Status changed from New to Closed"
        details: j.visible_details.map { |d| { property: d.property, name: d.prop_key, text: view.show_detail(d, true) } }
      }
    end
  end
end
