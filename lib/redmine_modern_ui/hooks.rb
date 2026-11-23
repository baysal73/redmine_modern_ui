# frozen_string_literal: true

module RedmineModernUi
  class Hooks < Redmine::Hook::ViewListener
    # Opt-out checkbox on "My account"
    render_on :view_my_account, partial: 'hooks/modern_ui_my_account'
  end
end
