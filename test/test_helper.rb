# frozen_string_literal: true

# Loads Redmine's own test helper (the plugin lives in redmine/plugins/redmine_modern_ui).
require File.expand_path('../../../test/test_helper', __dir__)

module ModernUiTestHelpers
  FIXTURES = %i[projects users email_addresses user_preferences roles members member_roles issues issue_statuses
                issue_categories versions trackers projects_trackers enabled_modules enumerations workflows
                journals journal_details custom_fields custom_values custom_fields_trackers custom_fields_projects].freeze

  def log_in(user_id)
    @request.session[:user_id] = user_id
  end

  def json
    JSON.parse(response.body)
  end

  def with_plugin_settings(overrides)
    original = Setting.plugin_redmine_modern_ui
    Setting.plugin_redmine_modern_ui = RedmineModernUi::DEFAULTS.merge(overrides)
    yield
  ensure
    Setting.plugin_redmine_modern_ui = original
  end
end
