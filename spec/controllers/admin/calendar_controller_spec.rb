require "rails_helper"

RSpec.describe Admin::CalendarController, type: :controller do
  render_views

  let!(:space) { create(:space) }
  let!(:admin_user) { create(:user, :admin, space: space) }
  let!(:staff_members) { create_list(:user, 2, :staff) }
  let!(:staff_space) do
    create(:staff_space, user: staff_members.first, space: space, color: "#FF00FF")
  end

  before do
    session[:user_id] = admin_user.id
    session[:expires_at] = DateTime.tomorrow.end_of_day
  end

  # describe "GET #index" do
  #   it "renders the index template with assigned variables" do
  #     get :index
  #     expect(response).to be_successful
  #     expect(assigns(:spaces)).to include(space)
  #     expect(assigns(:colors)).to all(include(:name, :color, :id))
  #   end
  # end

  describe "GET #unavailabilities_json" do
    let!(:recent_unavail) do
      create(
        :staff_unavailability,
        user: staff_members.first,
        start_time: 1.day.from_now,
        end_time: 1.day.from_now + 2.hours,
        title: "Out for appointment"
      )
    end

    let!(:old_unavail) do
      create(
        :staff_unavailability,
        user: staff_members.first,
        start_time: 3.months.ago,
        end_time: 3.months.ago + 2.hours,
        recurrence_rule: nil,
        title: "Old PTO"
      )
    end

#     it "returns current unavailabilities JSON for valid space" do
#       get :unavailabilities_json, params: { id: space.id }, format: :json
#       expect(response).to be_successful
#       json = JSON.parse(response.body)
#       expect(json.first["unavailabilities"].map do |u|
#  u["title"] end).to include("🚫 #{staff_members.first.name} - Out for appointment")
#     end

    # it "skips old unavailabilities without recurrence" do
    #   get :unavailabilities_json, params: { id: space.id }, format: :json
    #   titles = JSON.parse(response.body).first["unavailabilities"].map { |u| u["title"] }
    #   expect(titles).not_to include("🚫 #{staff_members.first.name} - Old PTO")
    # end
  end

  describe "GET #imported_calendars_json" do
    let!(:calendar_record) do
      create(
        :staff_needed_calendar,
        space: space,
        calendar_url: "http://example.com/fake.ics",
        name: "Test Calendar",
        color: "#123456"
      )
    end

    before do
      allow(controller.helpers).to receive(:parse_ics_calendar).and_return([
        {
          name: "Test Calendar",
          events: [{ title: "Event A", start: Time.now, end: Time.now + 1.hour }]
        }
      ])
    end

    it "returns parsed calendar events" do
      get :imported_calendars_json, params: { id: space.id }, format: :json
      expect(response).to be_successful
      json = JSON.parse(response.body)
      expect(json.first["events"].first["title"]).to eq("Event A")
    end
  end

  describe "POST #update_color" do
    it "updates the staff color if valid" do
      post :update_color, params: {
        user_id: staff_members.first.id,
        color: "#00FF00"
      }
      expect(response).to be_successful
      expect(flash[:notice]).to eq("Color updated successfully")
      expect(staff_space.reload.color).to eq("#00FF00")
    end

    it "does not update without color" do
      post :update_color, params: {
        user_id: staff_members.first.id
      }
      expect(flash[:alert]).to eq("An error occurred, try again later.")
    end

    it "does not update if user not in space" do
      other_user = create(:user, :staff)
      post :update_color, params: {
        user_id: other_user.id,
        color: "#00FF00"
      }
      expect(flash[:alert]).to eq("An error occurred, try again later.")
    end
  end
end
