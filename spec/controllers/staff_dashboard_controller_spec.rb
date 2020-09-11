require 'rails_helper'
include FilesTestHelper

RSpec.describe StaffDashboardController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @space = create(:space)
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @admin.id
  end

  describe 'GET /index' do
    context 'logged as regular user' do
      it 'should redirect to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end

    context 'logged as admin' do
      it 'should return 200' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /import_excel" do

    context "import excel" do

      it 'should sign in users using the excel file' do
        create(:user, :regular_user, username: "Bob1")
        create(:user, :regular_user, email: "bob@bob.com")
        create(:user, :regular_user, name: "Bob Bob Bob")
        expect{ post :import_excel, params: {file: fixture_file_upload(Rails.root.join('spec/support/assets', 'excel-login.xlsx'), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')} }.to change(LabSession, :count).by(3)
        expect(response).to redirect_to staff_dashboard_index_path
        expect(flash[:notice]).to eq("The file has been processed and users have been signed in ! ")
        expect(flash[:alert_yellow]).to eq("Please note that 3 user(s) did not get signed in because they were not found in the system.")
        expect(flash[:alert]).to eq("Users with error: john doe 123, johnnnnnn, joeeee@joeeee.com")
      end

    end

  end

  describe "PUT /sign_out_all_users" do

    context "sign out all users" do

      it 'should sign out all users' do
        user = create(:user, :regular_user)
        lab1 = LabSession.create(user_id: @admin.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
        lab2 = LabSession.create(user_id: user.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
        put :sign_out_all_users
        expect(response).to redirect_to staff_dashboard_index_path(space_id: @space.id)
        expect(LabSession.find(lab1.id).sign_out_time < DateTime.now)
        expect(LabSession.find(lab2.id).sign_out_time < DateTime.now)
      end

    end

  end

  describe "PUT /sign_out_all_users" do

    context "sign out all users" do

      it 'should sign out all users' do
        user = create(:user, :regular_user)
        lab1 = LabSession.create(user_id: @admin.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
        lab2 = LabSession.create(user_id: user.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
        put :sign_out_all_users
        expect(response).to redirect_to staff_dashboard_index_path(space_id: @space.id)
        expect(LabSession.find(lab1.id).sign_out_time < DateTime.now)
        expect(LabSession.find(lab2.id).sign_out_time < DateTime.now)
      end

    end

  end

  describe "PUT /sign_in_users" do

    context "sign in" do

      it 'should sign in users' do
        user = create(:user, :regular_user)
        put :sign_in_users, params: {added_users: user.username}
        expect(response).to redirect_to staff_dashboard_index_path(space_id: Space.first.id)
        expect(LabSession.last.sign_out_time > DateTime.now)
      end

    end

  end

  describe "PUT /change_space" do

    context "change space" do

      it 'should change space' do
        lab1 = LabSession.create(user_id: @admin.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
        new_space = create(:space)
        expect{ put :change_space, params: {space_id: new_space.id} }.to change(LabSession, :count).by(1)
        expect(response).to redirect_to staff_index_url
        expect(LabSession.last.sign_out_time > DateTime.now)
        expect(LabSession.find(lab1.id).sign_out_time < DateTime.now)
      end

    end

  end

  describe "PUT /link_rfid" do

    context "link" do

      it 'should link rfid' do
        user = create(:user, :regular_user)
        Rfid.create(card_number: "abc")
        put :link_rfid, params: {user_id: user.id, card_number: "abc"}
        expect(response).to have_http_status(302)
        expect(Rfid.find_by_card_number("abc").user_id).to eq(user.id)
      end

    end

  end

  describe "PUT /unlink_rfid" do

    context "unlink" do

      it 'should unlink rfid' do
        PiReader.create(pi_mac_address: "12:34:56:78:90", pi_location: @space.name)
        Rfid.create(card_number: "abc", user_id: @admin.id)
        LabSession.create(user_id: @admin.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
        put :unlink_rfid, params: {card_number: "abc"}
        expect(response).to have_http_status(302)
        expect(Rfid.find_by_card_number("abc").user_id).to be_nil
      end

    end

  end

  describe "GET /search" do

    context "blank query" do

      it 'should redirect' do
        user = create(:user, :regular_user)
        LabSession.create(user_id: user.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
        get :search, params: {query: ""}
        expect(response).to have_http_status(302)
        expect(flash[:alert]).to eq('Invalid parameters!')
      end

    end

    context "normal query" do

      it 'should search a result' do
        user = create(:user, :regular_user)
        LabSession.create(user_id: user.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
        get :search, params: {query: user.name}
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@users).first).to eq(User.find(user.id))
      end

    end

  end

  describe "GET /populate_users" do

    context "populate_users" do

      it 'should get the users that has been searched' do
        user = create(:user, :regular_user)
        get :populate_users, params: {search: user.name}
        expect(JSON.parse(response.body)['users'][0]['id']).to eq(user.id)
      end

    end

  end

end
