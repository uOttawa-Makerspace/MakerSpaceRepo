# frozen_string_literal: true

require "rails_helper"

# Forms get data-turbo="false" (application.js), so Turbo never shows
# data-turbo-confirm; a delegated capture handler does.
RSpec.describe "Confirm dialogs", type: :system do
  let(:user) { create(:user, :regular_user) }

  before do
    allow_any_instance_of(Octokit::Client).to receive(:login).and_raise(Octokit::Unauthorized)
    user.avatar.attach(io: StringIO.new(File.binread(Rails.root.join("public/default-avatar.png"))), filename: "a.png", content_type: "image/png")
    log_in_as(user)
    visit settings_profile_path
  end

  it "does not remove the avatar when the confirmation is dismissed" do
    dismiss_confirm { click_button I18n.t("settings.profile.delete_avatar") }
    expect(page).to have_current_path(settings_profile_path)
    expect(user.reload.avatar).to be_attached
  end

  it "removes the avatar when the confirmation is accepted" do
    accept_confirm { click_button I18n.t("settings.profile.delete_avatar") }
    expect(page).to have_no_button(I18n.t("settings.profile.delete_avatar"))
    expect(user.reload.avatar).not_to be_attached
  end
end
