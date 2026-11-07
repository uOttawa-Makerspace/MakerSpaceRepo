# frozen_string_literal: true

require "rails_helper"

# A deleted account is hidden from public pages only: staff and admin pages keep showing the person,
# marked "(deleted account)", and pages that non-staff users open show a neutral label or nothing.
RSpec.describe "Pages that show a deleted user", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:gone) { create(:user, name: "Gone Person", username: "goneperson", email: "gone.person@uottawa.ca") }
  let(:gone_supervisor) { create(:user, :admin, name: "Gone Supervisor", username: "gonesupervisor") }
  let(:space) { create(:space) }

  def delete_account!(*users)
    users.each { |user| user.update_columns(deleted: true) }
  end

  def page_text
    Nokogiri::HTML(response.body).text.squish
  end

  def sign_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  describe "job order timeline (staff and admin)" do
    before { seed_job_statuses! }

    let(:order) do
      make_job_order!(owner: create(:user)).tap do |o|
        o.job_order_statuses.create!(job_status: JobStatus.being_processed, user: gone)
      end
    end

    it "names a deleted actor with the deleted-account mark and no profile link" do
      delete_account!(gone)
      sign_in!(staff)
      get job_order_timeline_modal_path(order)

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("(By: Gone Person (deleted account))")
      expect(page_text).not_to include("Unknown")
      expect(response.body).not_to include(user_path(username: "goneperson"))
    end

    it "still links a live actor to the profile" do
      sign_in!(staff)
      get job_order_timeline_modal_path(order)

      expect(response.body).to include(user_path(username: "goneperson"))
    end

    it "is closed to the customer" do
      delete_account!(gone)
      sign_in!(order.user)
      get job_order_timeline_modal_path(order)

      expect(response).to redirect_to(root_path)
      expect(response.body).not_to include("Gone Person")
    end
  end

  describe "volunteer shadowing shifts" do
    before do
      ShadowingHour.create!(user: gone, space: space, event_id: "evt-1", start_time: 1.day.from_now, end_time: 1.day.from_now + 1.hour)
      delete_account!(gone)
    end

    it "names the deleted volunteer and shows the email to staff" do
      sign_in!(staff)
      get shadowing_shifts_volunteers_path

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Gone Person (deleted account)", "gone.person@uottawa.ca")
      expect(response.body).to include("cancel Gone Person (deleted account)&#39;s shadowing shift")
      expect(response.body).not_to include(user_path(username: "goneperson"))
    end

    it "does not show a volunteer the list of other volunteers' shifts" do
      sign_in!(create(:user, :volunteer_with_volunteer_program))
      get shadowing_shifts_volunteers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Gone Person", "gone.person@uottawa.ca", "goneperson")
    end
  end

  describe "tap box console (staff)" do
    it "names the user of a log row and keeps the name in the search string" do
      TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "Door opened", user: gone)
      delete_account!(gone)
      sign_in!(staff)
      get staff_tap_box_console_path

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Gone Person (deleted account)")
      expect(response.body).to include("gone person")
    end
  end

end
