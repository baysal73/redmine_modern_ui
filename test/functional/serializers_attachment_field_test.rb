# frozen_string_literal: true

require_relative '../test_helper'

# File custom fields (used on contacts): hidden in issue forms, shown with the current file when asked for.
class SerializersAttachmentFieldTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :issue_statuses, :enumerations, :custom_fields

  def setup
    @field = IssueCustomField.create!(name: 'Logo', field_format: 'attachment', is_for_all: true, tracker_ids: [1], visible: true)
    @cv = Issue.new(project_id: 1, tracker_id: 1).custom_field_values.find { |v| v.custom_field_id == @field.id }
  end

  def test_not_offered_by_default
    assert_nil RedmineModernUi::Serializers.custom_field_form(@cv, nil)
  end

  def test_offered_without_file_when_requested
    form = RedmineModernUi::Serializers.custom_field_form(@cv, nil, attachments: true)
    assert_equal 'attachment', form[:kind]
    assert_nil form[:file]
    assert_equal @field.id, form[:id]
  end

  def test_offered_with_current_file
    att = Attachment.create!(file: Rack::Test::UploadedFile.new(StringIO.new('x'), 'text/plain', original_filename: 'logo.txt'), author: User.find(2))
    @cv.instance_variable_set(:@value, att.id.to_s) # Redmine only accepts ids of files already attached to the record
    form = RedmineModernUi::Serializers.custom_field_form(@cv, nil, attachments: true)
    assert_equal 'logo.txt', form[:file][:filename]
    assert_match %r{/attachments/download/#{att.id}/logo.txt\z}, form[:file][:url]
  end
end
