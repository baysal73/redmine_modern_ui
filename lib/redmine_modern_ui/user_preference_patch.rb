# frozen_string_literal: true

module RedmineModernUi
  # Per-user opt-out, stored in UserPreference#others (no migration needed).
  module UserPreferencePatch
    def self.prepended(base)
      base.safe_attributes 'modern_ui_redirect'
    end

    def modern_ui_redirect
      self[:modern_ui_redirect]
    end

    def modern_ui_redirect=(value)
      self[:modern_ui_redirect] = value
    end
  end
end
