# frozen_string_literal: true

require_relative 'redmine_modern_ui/calendar_backend'
require_relative 'redmine_modern_ui/saved_filters'

module RedmineModernUi
  VERSION = '0.1.4'

  DEFAULTS = {
    'redirect_after_login' => '1', # send users to the new UI after login
    'base_path' => 'app',          # mount point; changing it needs a restart
    'modern_login' => '1',         # modern sign-in page
    'brand_primary' => '',         # company colours (hex); empty = built-in colours
    'brand_gold' => '',
    'brand_grey' => '',
    'logo_data' => ''              # data URI of the uploaded logo
  }.freeze

  module_function

  def settings
    DEFAULTS.merge(Setting.plugin_redmine_modern_ui.to_h)
  rescue StandardError
    DEFAULTS
  end

  def modern_login?
    settings['modern_login'].to_s != '0'
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

  HEX = /\A#[0-9a-f]{6}\z/i
  LOGO = %r{\Adata:image/(?:png|jpeg|gif|webp|svg\+xml);base64,[A-Za-z0-9+/=]+\z}
  LOGO_MAX = 600_000

  def brand_color(key)
    v = settings[key].to_s.strip
    v.match?(HEX) ? v.downcase : nil
  end

  # Logo as data URI, only if it looks like an image we accept (rendered via <img>, so SVG scripts never run).
  def logo_data
    v = settings['logo_data'].to_s.strip
    v.size <= LOGO_MAX && v.match?(LOGO) ? v : nil
  end

  def brand
    logo = logo_data
    { primary: brand_color('brand_primary'), gold: brand_color('brand_gold'), grey: brand_color('brand_grey'),
      logo: logo ? Digest::MD5.hexdigest(logo)[0, 10] : nil }
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
