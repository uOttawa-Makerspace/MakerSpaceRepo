# frozen_string_literal: true

require "rails_helper"

# Flash messages set by a redirect that lands on a staff area page
# (layouts/staff_area) are shown on that page, through the shared
# layouts/flash partial, and are not shown again on the next page.
RSpec.describe "Staff area flash messages", type: :request do
  let(:password) { "asa32A353#" }
  let(:staff) { create(:user, :staff) }
  let(:notice) { "You've successfully created an announcement for Volunteers" }
  let(:alert) { "Please select another public goal" }

  before do
    post login_authentication_path, params: { username_email: staff.username, password: password }
    expect(response).to redirect_to(root_path)
  end

  def flash_banners
    Nokogiri::HTML(response.body).css("#flash .alert[role=alert]")
  end

  def create_announcement(goal)
    post announcements_path, params: { announcement: { description: "Volunteer meeting", public_goal: goal } }
  end

  it "shows a notice once on the staff area page the redirect lands on, and not on the next page" do
    create_announcement("volunteer")
    expect(response).to redirect_to(announcements_path)

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(flash_banners.map { |banner| banner.text.strip }).to eq([notice])
    expect(flash_banners.first[:class]).to include("alert-success")

    get about_path
    expect(response.body).not_to include(notice)
  end

  it "shows an alert once on the staff area page the redirect lands on, and not on the next page" do
    create_announcement("all")
    expect(response).to redirect_to(new_announcement_path)

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(flash_banners.map { |banner| banner.text.strip }).to eq([alert])
    expect(flash_banners.first[:class]).to include("alert-danger")

    get announcements_path
    expect(response.body).not_to include(alert)
  end
end
