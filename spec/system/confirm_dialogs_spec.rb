# frozen_string_literal: true

require "rails_helper"

# Forms get data-turbo="false" (application.js), so Turbo never shows
# data-turbo-confirm; a delegated capture handler does.
RSpec.describe "Confirm dialogs", type: :system do
  let(:user) { create(:user, :regular_user) }

  before do
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

  # Builds a throwaway form on the page; its own submit listener records runs and
  # swallows the submit so nothing navigates.
  def add_form(classes:, attrs:)
    page.execute_script(<<~JS)
      window.listenerRuns = 0;
      const f = document.createElement("form");
      f.id = "probe"; f.className = "#{classes}"; f.action = "/nowhere"; f.method = "post";
      #{attrs.map { |k, v| "f.setAttribute('#{k}', '#{v}');" }.join}
      f.addEventListener("submit", (e) => { window.listenerRuns += 1; e.preventDefault(); });
      const b = document.createElement("button");
      b.type = "submit"; b.id = "probe-go"; b.textContent = "Probe go";
      f.appendChild(b);
      document.body.prepend(f);
    JS
  end

  it "does not run per-form submit listeners when the confirmation is dismissed" do
    add_form(classes: "", attrs: { "data-confirm" => "Sure?" })
    dismiss_confirm("Sure?") { click_button "Probe go" }
    expect(page.evaluate_script("window.listenerRuns")).to eq(0)
    accept_confirm("Sure?") { click_button "Probe go" }
    expect(page.evaluate_script("window.listenerRuns")).to eq(1)
  end

  it "prompts natively for a .useTurbo form that only has legacy data-confirm" do
    add_form(classes: "useTurbo", attrs: { "data-confirm" => "Legacy?" })
    dismiss_confirm("Legacy?") { click_button "Probe go" }
    expect(page.evaluate_script("window.listenerRuns")).to eq(0)
  end

  def add_link(classes:, attrs:)
    page.execute_script(<<~JS)
      window.linkRuns = 0;
      const a = document.createElement("a");
      a.id = "probe-link"; a.className = "#{classes}"; a.href = "#probe-hit"; a.textContent = "Probe link";
      #{attrs.map { |k, v| "a.setAttribute('#{k}', '#{v}');" }.join}
      a.addEventListener("click", (e) => { window.linkRuns += 1; e.preventDefault(); });
      document.body.prepend(a);
    JS
  end

  it "prompts natively for a .useTurbo link with data-turbo-confirm but no data-turbo-method" do
    add_link(classes: "useTurbo", attrs: { "data-turbo-confirm" => "Visit?" })
    dismiss_confirm("Visit?") { click_link "Probe link" }
    expect(page.evaluate_script("window.linkRuns")).to eq(0)
    accept_confirm("Visit?") { click_link "Probe link" }
    expect(page.evaluate_script("window.linkRuns")).to eq(1)
  end

  it "uses the submitter's own message over the form's" do
    add_form(classes: "", attrs: { "data-confirm" => "Form?" })
    page.execute_script("document.getElementById('probe-go').setAttribute('data-confirm', 'Button?')")
    accept_confirm("Button?") { click_button "Probe go" }
    expect(page.evaluate_script("window.listenerRuns")).to eq(1)
  end

  it "does not switch Turbo off for an explicit data-turbo=true form" do
    add_form(classes: "", attrs: { "data-turbo" => "true" })
    click_button "Probe go"
    expect(page.evaluate_script("document.getElementById('probe').getAttribute('data-turbo')")).to eq("true")
  end
end
