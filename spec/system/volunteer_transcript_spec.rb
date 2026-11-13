# frozen_string_literal: true

require "rails_helper"

# The volunteer transcript is a standalone printable page. Its stylesheet
# (Bootstrap's default theme and Font Awesome) comes from the app's own build,
# so the page loads nothing from another host.
RSpec.describe "Volunteer transcript page", type: :system, skip_bullet: true do
  include BrowserAuthHelper

  def style_of(selector, property, pseudo = nil)
    page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json}), #{pseudo.to_json})[#{property.to_json}]")
  end

  it "styles the page from the app's own assets, with no request to another host" do
    user = create(:user, :volunteer_with_volunteer_program)
    log_in_as(user)
    visit transcript_volunteers_path
    expect(page).to have_text("Official Volunteer Service Record")

    # Bootstrap's default primary button and the page's own card styles apply.
    expect(style_of(".btn-primary", "backgroundColor")).to eq("rgb(13, 110, 253)")
    expect(style_of(".transcript-card", "maxWidth")).to eq("900px")
    expect(style_of(".fa-print", "fontFamily", "::before")).to include("Font Awesome")

    origin = page.evaluate_script("location.origin")
    resources = page.evaluate_script("performance.getEntriesByType('resource').map(e => e.name)")
    expect(resources).to include(a_string_matching(/\.css\z/))
    expect(resources).to all(start_with("#{origin}/"))
  end
end
