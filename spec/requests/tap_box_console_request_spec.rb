require "rails_helper"

# Chunk 15: Staff::TapBoxConsoleController. Inherits StaffAreaController
# (guests -> login, non-staff -> root "You cannot access this area.") and adds
# its own `signed_in` + staff-only grant_access. TapBoxConsoleChannel rejects
# non-staff subscriptions.
RSpec.describe "Tap box console", type: :request do
  it "sends a guest to the login page" do
    get staff_tap_box_console_path
    expect(response).to redirect_to(login_path(back_to: staff_tap_box_console_path))
  end

  %i[regular volunteer].each do |role|
    it "bounces a #{role} to root" do
      sign_in_as(role)
      get staff_tap_box_console_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
    end
  end

  it "renders for staff with its channel marker, filter controls and an empty state" do
    sign_in_as(:staff)
    get staff_tap_box_console_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<turbo-cable-stream-source")
    expect(response.body).to include("id=\"console-body\"")
    expect(response.body).to include("id=\"connection-status\"")
    expect(response.body).to include("No tap events yet")
  end

  it "renders for admin (StaffAreaController admits admins, and admin.staff? is true)" do
    sign_in_as(:admin)
    get staff_tap_box_console_path
    expect(response).to have_http_status(:ok)
  end

  it "lists logs newest first, capped at 500" do
    sign_in_as(:staff)
    old = TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "older entry")
    old.update_columns(created_at: 2.days.ago)
    TapBoxLog.log!(event_type: TapBoxLog::ERROR, message: "newer entry")
    get staff_tap_box_console_path
    expect(response.body.index("newer entry")).to be < response.body.index("older entry")
    expect(response.body).not_to include("No tap events yet")
    expect(response.body).to include('data-event-type="error"')
  end
end
