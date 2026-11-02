require "rails_helper"
include FilesTestHelper

RSpec.describe StaffDashboardController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  before(:each) do
    @admin = create(:user, :admin)
    @space = create(:space)
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @admin.id
  end

  describe "GET /index" do
    context "logged as regular user" do
      it "should redirect to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end

    context "logged as admin" do
      it "should return 200" do
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /refresh_capacity" do
    context "logged as admin" do
      it "should return 200" do
        get :refresh_capacity, xhr: true
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /import_excel" do
    context "import excel" do
      it "should sign in users using the excel file" do
        create(:user, :regular_user, username: "Bob1")
        create(:user, :regular_user, email: "bob@uottawa.ca")
        create(:user, :regular_user, name: "Bob Bob Bob")
        expect {
          post :import_excel,
               params: {
                 file:
                   fixture_file_upload(
                     Rails.root.join("spec/support/assets", "excel-login.xlsx"),
                     "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                   )
               }
        }.to change(LabSession, :count).by(3)
        expect(response).to redirect_to staff_dashboard_index_path
        expect(flash[:notice]).to eq(
          "The file has been processed and users have been signed in ! "
        )
        expect(flash[:alert_yellow]).to eq(
          "Please note that 3 user(s) did not get signed in because they were not found in the system."
        )
        expect(flash[:alert]).to eq(
          "Users with error: john doe 123, johnnnnnn, joeeee@uottawa.ca"
        )
      end
    end
  end

  describe "POST /sign_out_all_users" do
    context "sign out all users" do
      it "should sign out all users" do
        freeze_time do
          user = create(:user, :regular_user)
          lab1 =
            LabSession.create(
              user_id: @admin.id,
              space_id: @space.id,
              sign_in_time: 1.hour.ago,
              sign_out_time: DateTime.now.tomorrow
            )
          lab2 =
            LabSession.create(
              user_id: user.id,
              space_id: @space.id,
              sign_in_time: 1.hour.ago,
              sign_out_time: DateTime.now.tomorrow
            )
          # Previous session
          previous_end = 1.day.ago + 3.hours
          lab3 =
            LabSession.create(
              user_id: user.id,
              space_id: @space.id,
              sign_in_time: 1.day.ago,
              sign_out_time: previous_end
            )
          post :sign_out_all_users
          expect(response).to redirect_to staff_dashboard_index_path(
                        space_id: Space.first.id
                      )
          # Active sessions end exactly now (time is frozen)
          expect(LabSession.find(lab1.id).sign_out_time).to eq(Time.zone.now)
          expect(LabSession.find(lab2.id).sign_out_time).to eq(Time.zone.now)
          # ensure previous lab sessions are left intact
          expect(LabSession.find(lab3.id).sign_out_time).to eq(previous_end)
        end
      end
    end
  end

  describe "PUT /sign_in_users" do
    context "sign in" do
      it "should sign in users" do
        user = create(:user, :regular_user)
        freeze_time do
          put :sign_in_users, params: { added_users: user.username }
          expect(response).to redirect_to staff_dashboard_index_path(
                        space_id: Space.first.id
                      )
          session_row = LabSession.last
          expect(session_row.user_id).to eq(user.id)
          expect(session_row.space_id).to eq(Space.first.id)
          expect(session_row.sign_in_time).to eq(Time.zone.now)
          # A staff-dashboard sign in lasts exactly 6 hours
          expect(session_row.sign_out_time).to eq(Time.zone.now + 6.hours)
        end
      end
    end
  end

  describe "PUT /sign_out_users" do
    context "sign out" do
      it "should sign out one user only" do
        user1 = create(:user, :regular_user)
        user2 = create(:user, :regular_user)
        keep_signed = create(:user, :regular_user)
        put :sign_in_users,
            params: {
              added_users: [
                user1.username,
                user2.username,
                keep_signed.username
              ]
            }

        put :sign_out_users,
            params: {
              dropped_users: [user1.username, user2.username]
            }
        expect(response).to redirect_to staff_dashboard_index_path
        expect(LabSession.active_for_user(user1).count).to eq 0
        expect(LabSession.active_for_user(user2).count).to eq 0
        expect(LabSession.active_for_user(keep_signed).count).to eq 1
      end
    end
  end

  describe "PUT /change_space" do
    context "change space" do
      it "should change space" do
        sign_out_time = DateTime.now.tomorrow.change(usec: 0)
        lab1 =
          LabSession.create(
            user_id: @admin.id,
            space_id: @space.id,
            sign_in_time: 1.hour.ago,
            sign_out_time: sign_out_time
          )
        new_space = create(:space)
        expect {
          put :change_space, params: { space_id: new_space.id }
        }.to change(LabSession, :count).by(0)
        expect(@controller.instance_variable_get(:@space).id).to eq(
          new_space.id
        )
        expect(response).to have_http_status(302)
        expect(@admin.reload.space_id).to eq(new_space.id)
        # changing space does not touch the user's open sessions
        expect(LabSession.last.id).to eq(lab1.id)
        expect(LabSession.find(lab1.id).sign_out_time).to eq(sign_out_time)
        expect(LabSession.find(lab1.id).space_id).to eq(@space.id)
      end
    end
  end

  describe "PUT /link_rfid" do
    context "link" do
      it "should link rfid" do
        user = create(:user, :regular_user)
        Rfid.create(card_number: "abc")
        put :link_rfid, params: { user_id: user.id, card_number: "abc" }
        expect(response).to have_http_status(302)
        expect(Rfid.find_by_card_number("abc").user_id).to eq(user.id)
      end
    end
  end

  describe "PUT /unlink_rfid" do
    context "unlink" do
      it "should unlink rfid" do
        PiReader.create(
          pi_mac_address: "12:34:56:78:90",
          pi_location: @space.name
        )
        Rfid.create(card_number: "abc", user_id: @admin.id)
        LabSession.create(
          user_id: @admin.id,
          space_id: @space.id,
          sign_in_time: 1.hour.ago,
          sign_out_time: DateTime.now.tomorrow
        )
        put :unlink_rfid, params: { card_number: "abc" }
        expect(response).to have_http_status(302)
        expect(Rfid.find_by_card_number("abc").user_id).to be_nil
      end
    end
  end

  describe "GET /search" do
    context "blank query" do
      it "should redirect" do
        user = create(:user, :regular_user)
        LabSession.create(
          user_id: user.id,
          space_id: @space.id,
          sign_in_time: 1.hour.ago,
          sign_out_time: DateTime.now.tomorrow
        )
        get :search, params: { query: "" }
        expect(response).to have_http_status(302)
        expect(flash[:alert]).to eq("No search parameters.")
      end
    end

    context "normal query" do
      it "should search a result" do
        user = create(:user, :regular_user)
        LabSession.create(
          user_id: user.id,
          space_id: @space.id,
          sign_in_time: 1.hour.ago,
          sign_out_time: DateTime.now.tomorrow
        )
        get :search, params: { query: user.name }
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@users).first).to eq(
          User.find(user.id)
        )
      end
    end
  end

  describe "GET /populate_users" do
    context "populate_users" do
      it "should get the users that has been searched" do
        user = create(:user, :regular_user)
        get :populate_users, params: { search: user.name }
        expect(JSON.parse(response.body)["users"][0]["name"]).to eq(user.name)
      end
    end
  end
end
