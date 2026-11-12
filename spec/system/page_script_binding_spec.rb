# frozen_string_literal: true

require "rails_helper"

# Page scripts bind to elements their page may not contain; none may raise a
# console error (the system spec harness fails an example on any SEVERE entry).
RSpec.describe "Page scripts on pages lacking some of their elements", type: :system do
  let(:training) { create(:training, has_badge: true) }
  let(:session_record) { create(:training_session, training: training, level: "Intermediate") }
  let(:earner) { create(:user, :regular_user) }
  let!(:cert) { create(:certification, user: earner, training_session: session_record, training: training, level: "Intermediate") }

  it "lets the badge list page load" do
    log_in_as(earner, to: badges_path)
    expect(page).to have_css("#search_bar")
  end

  it "keeps the badge page download button working" do
    log_in_as(earner, to: badge_path(cert))
    expect(page).to have_css("#add-to-linkedin")
    expect(page).to have_css("#linkedin")
  end
end
