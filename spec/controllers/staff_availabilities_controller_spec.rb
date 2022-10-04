require "rails_helper"

RSpec.describe StaffAvailabilitiesController, type: :controller do
  before(:all) do
    @staff = create(:user, :staff)
    @default_space = create(:space)
    StaffSpace.create(space_id: @default_space.id, user_id: @staff.id)
  end

  before(:each) { session[:user_id] = @staff.id }

  describe "GET /index" do
    context "logged as staff" do
      it "should return 200 response" do
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as regular user" do
      it "should redirect user to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq(
          "You cannot access this area. If you think you should be able, try asking your manager if you were added in one of the spaces."
        )
      end
    end
  end

  describe "GET /get_availabilities" do
    context "get availabilities" do
      it "should get all the availabilities from the staffs" do
        sa1 = create(:staff_availability, user_id: @staff.id)
        sa2 = create(:staff_availability, user_id: @staff.id)
        create(:staff_availability)

        get :get_availabilities
        expect(response).to have_http_status(:success)
        expect(response.body).to eq(
          [
            {
              title: "Unavailable",
              id: sa1.id,
              daysOfWeek: [sa1.day],
              startTime: sa1.start_time.strftime("%H:%M"),
              endTime: sa1.end_time.strftime("%H:%M")
            },
            {
              title: "Unavailable",
              id: sa2.id,
              daysOfWeek: [sa2.day],
              startTime: sa2.start_time.strftime("%H:%M"),
              endTime: sa2.end_time.strftime("%H:%M")
            }
          ].to_json
        )
      end
    end
  end

  describe "GET /new" do
    context "logged as admin" do
      it "should return a 200" do
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /edit" do
    context "logged as admin" do
      it "should return 200 response" do
        sa1 = create(:staff_availability, user_id: @staff.id)
        get :edit, params: { id: sa1.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /create" do
    context "logged as admin" do
      it "should create a staff availability" do
        sa_params =
          FactoryBot.attributes_for(:staff_availability, user_id: @staff.id)
        expect {
          post :create, params: { staff_availability: sa_params }
        }.to change(StaffAvailability, :count).by(1)
        expect(response).to redirect_to staff_availabilities_path
      end
    end
  end

  describe "PATCH /update" do
    context "logged as staff" do
      it "should update the staff_availability" do
        sa1 = create(:staff_availability, user_id: @staff.id)
        time = Time.now.utc
        patch :update,
              params: {
                id: sa1.id,
                staff_availability: {
                  start_time: time
                }
              }
        expect(response).to redirect_to staff_availabilities_path
        expect(
          StaffAvailability.find(sa1.id).start_time.utc.strftime("%H:%M")
        ).to eq(time.strftime("%H:%M"))
      end
    end
  end

  describe "DELETE /destroy" do
    context "logged as admin" do
      it "should destroy the staff availablity" do
        sa1 = create(:staff_availability, user_id: @staff.id)
        expect { delete :destroy, params: { id: sa1.id } }.to change(
          StaffAvailability,
          :count
        ).by(-1)
        expect(response).to redirect_to staff_availabilities_path
      end
    end
  end

  after(:all) { StaffAvailability.destroy_all }
end
