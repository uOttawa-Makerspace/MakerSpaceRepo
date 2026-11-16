# frozen_string_literal: true

require "rails_helper"

# Confirming buttons are rendered disabled and carry the confirmation Stimulus
# controller, which enables them once connected and asks before they act.
RSpec.describe "Confirm dialogs", type: :system do
  let(:user) { create(:user, :regular_user) }

  before do
    user.avatar.attach(io: StringIO.new(File.binread(Rails.root.join("public/default-avatar.png"))), filename: "a.png", content_type: "image/png")
    log_in_as(user, to: settings_profile_path)
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

  # Adds a disabled confirming button the way the server renders one and reports
  # whether it was disabled at insertion; a click listener further up the page
  # records the clicks that were not cancelled.
  def add_confirming_button
    page.evaluate_script(<<~JS)
      (() => {
        window.buttonRuns = 0;
        const b = document.createElement("button");
        b.type = "button"; b.id = "probe-go"; b.textContent = "Probe go"; b.disabled = true;
        b.dataset.controller = "confirmation";
        b.dataset.action = "click->confirmation#ask";
        b.dataset.confirmationMessageValue = "Sure?";
        document.body.addEventListener("click", (e) => { if (e.target === b) window.buttonRuns += 1; });
        document.body.prepend(b);
        return b.disabled;
      })()
    JS
  end

  it "keeps a confirming button disabled until the controller connects, then enables it" do
    expect(add_confirming_button).to be(true)
    expect(page).to have_button("Probe go", disabled: false)
  end

  it "lets the click through only when the confirmation is accepted" do
    add_confirming_button
    dismiss_confirm("Sure?") { click_button "Probe go" }
    expect(page.evaluate_script("window.buttonRuns")).to eq(0)
    accept_confirm("Sure?") { click_button "Probe go" }
    expect(page.evaluate_script("window.buttonRuns")).to eq(1)
  end

  # No helper waits for page scripts: a confirming button is rendered disabled and
  # Capybara's click_button only matches enabled buttons, so the click (and the
  # prompt it raises) waits for that button's own controller, on whichever page
  # is current. This one connects its controller late.
  it "waits for a confirming button whose controller connects late" do
    page.evaluate_script(<<~JS)
      (() => {
        window.buttonRuns = 0;
        const b = document.createElement("button");
        b.type = "button"; b.id = "late-go"; b.textContent = "Late go"; b.disabled = true;
        b.dataset.action = "click->confirmation#ask";
        b.dataset.confirmationMessageValue = "Sure?";
        document.body.addEventListener("click", (e) => { if (e.target === b) window.buttonRuns += 1; });
        document.body.prepend(b);
        setTimeout(() => { b.dataset.controller = "confirmation"; }, 400);
      })()
    JS
    accept_confirm("Sure?") { click_button "Late go" }
    expect(page.evaluate_script("window.buttonRuns")).to eq(1)
  end
end
