# frozen_string_literal: true

require "rails_helper"

# DOM-level characterization of the staff Tap Box Console: it renders the
# channel markers (turbo stream source + connection badge), the newest-first
# log table and the client-side filters. Real login.
RSpec.describe "Tap box console", type: :system do
  let(:staff) { create(:user, :staff) }
  let(:space) { create(:space) }

  before do
    TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "Reader registered", card_number: "CARD-INFO", space: space)
    TapBoxLog.log!(event_type: TapBoxLog::ERROR, message: "No space resolved", card_number: "CARD-ERR")
  end

  it "keeps a regular user out of the console" do
    log_in_as(create(:user, :regular_user))
    visit staff_tap_box_console_path
    expect(page).to have_current_path(root_path)
    expect(page).not_to have_css("#tap-box-console")
  end

  it "renders the channel markers, controls and log rows for staff" do
    log_in_as(staff)
    visit staff_tap_box_console_path

    expect(page).to have_css("h4", text: "Tap Box Debugger Console")
    expect(page).to have_css("turbo-cable-stream-source[channel='Turbo::StreamsChannel']", visible: :all)
    expect(page).to have_css("#connection-status.badge")
    expect(page).to have_select("filter-event-type", with_options: ["All events", "Card Tap", "Sign In", "Sign Out", "Error", "Warning", "Info", "Membership Check"])
    expect(page).to have_css("input#filter-search")
    expect(page).to have_button("Clear view")
    expect(page).to have_css("#console-body tr", count: 2)
    expect(page).to have_no_css("#empty-state")
    first_row = find("#console-body tr", match: :first)
    expect(first_row["data-event-type"]).to eq("error")
    expect(first_row).to have_text("CARD-ERR")
  end

  it "filters rows client-side by event type and by search text" do
    log_in_as(staff)
    visit staff_tap_box_console_path
    expect(page).to have_css("#console-body tr", count: 2)

    select "Error", from: "filter-event-type"
    expect(page).to have_css("#console-body tr", visible: :visible, count: 1)
    expect(page).to have_css("#console-body tr[data-event-type='error']", visible: :visible)
    expect(page).to have_css("#console-body tr[data-event-type='info']", visible: :hidden)

    select "All events", from: "filter-event-type"
    fill_in "filter-search", with: "card-info"
    expect(page).to have_css("#console-body tr", visible: :visible, count: 1)
    expect(page).to have_css("#console-body tr[data-event-type='info']", visible: :visible)
  end
end
