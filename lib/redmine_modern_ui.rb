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

  # Statuses the admin wants treated as "done" in the new UI although Redmine does not flag them as closed.
  def done_status_ids
    Array(settings['done_status_ids']).map(&:to_i).reject(&:zero?)
  end

  # status_id filter [operator, values] for "open" issues; plain Redmine "open" unless done statuses are configured.
  def open_status_filter
    return ['o', ['']] if done_status_ids.empty?

    ['!', (IssueStatus.where(is_closed: true).pluck(:id) + done_status_ids).uniq.map(&:to_s)]
  end

  def closed_status_filter
    return ['c', ['']] if done_status_ids.empty?

    ['=', (IssueStatus.where(is_closed: true).pluck(:id) + done_status_ids).uniq.map(&:to_s)]
  end

  def done_status?(status)
    status.is_closed? || done_status_ids.include?(status.id)
  end

  # Should this user land on the new UI after login?
  def redirect_after_login?(user)
    return false unless settings['redirect_after_login'] == '1'

    user.pref[:modern_ui_redirect].to_s != '0'
  end

  def apply_patches!
    require_relative 'redmine_modern_ui/account_controller_patch'
    require_relative 'redmine_modern_ui/user_preference_patch'
    AccountController.prepend(AccountControllerPatch) unless AccountController < AccountControllerPatch
    UserPreference.prepend(UserPreferencePatch) unless UserPreference < UserPreferencePatch
    require_relative 'redmine_modern_ui/hooks'
    require_relative 'redmine_modern_ui/serializers'
  end
end
