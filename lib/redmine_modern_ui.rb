# frozen_string_literal: true

module RedmineModernUi
  VERSION = '0.1.0'

  DEFAULTS = {
    'redirect_after_login' => '1', # send users to the new UI after login
    'base_path' => 'app'           # mount point; changing it needs a restart
  }.freeze

  module_function

  def settings
    DEFAULTS.merge(Setting.plugin_redmine_modern_ui.to_h)
  rescue StandardError
    DEFAULTS
  end

  # Mount path without slashes. Read at boot for the routes (needs restart to change).
  def base_path
    p = settings['base_path'].to_s.strip.gsub(%r{\A/+|/+\z}, '')
    p.match?(/\A[a-z0-9_\-]+\z/i) ? p : DEFAULTS['base_path']
  end

  # Should this user land on the new UI after login?
  def redirect_after_login?(user)
    return false unless settings['redirect_after_login'] == '1'

    user.pref['modern_ui_redirect'].to_s != '0'
  end

  def apply_patches!
    require_relative 'redmine_modern_ui/account_controller_patch'
    require_relative 'redmine_modern_ui/user_preference_patch'
    AccountController.prepend(AccountControllerPatch) unless AccountController < AccountControllerPatch
    UserPreference.prepend(UserPreferencePatch) unless UserPreference < UserPreferencePatch
    require_relative 'redmine_modern_ui/hooks'
  end
end
