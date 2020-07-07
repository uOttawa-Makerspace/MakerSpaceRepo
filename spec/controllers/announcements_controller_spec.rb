require 'rails_helper'

RSpec.describe AnnouncementsController, type: :controller do

  describe "index" do

    context 'index' do

      it 'should give a 200' do
        admin = create(:user, :admin_user)
        session[:user_id] = admin.id
        create(:announcement, :all)
        create(:announcement, :volunteer)
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@announcements).count).to eq(2)
      end

    end

    context 'testing with regular user' do

      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end

    end

  end

  describe 'new' do

    context 'new' do

      it 'should return a 200' do
        admin = create(:user, :admin_user)
        session[:user_id] = admin.id
        get :new
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "show" do

    context 'show' do

      it 'should access the show page with 200' do
        admin = create(:user, :admin_user)
        session[:user_id] = admin.id
        announcement = create(:announcement, :admin)
        get :show, params: {id: announcement.id}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "edit" do

    context 'edit' do

      it 'should access the edit page with 200' do
        admin = create(:user, :admin_user)
        session[:user_id] = admin.id
        announcement = create(:announcement, :admin)
        get :edit, params: {id: announcement.id}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe 'create' do

    context 'create' do

      it 'should create an announcement and redirect' do
        admin = create(:user, :admin_user)
        session[:user_id] = admin.id
        announcement_params =  FactoryBot.attributes_for(:announcement, :all)
        expect { post :create, params: {announcement: announcement_params} }.to change(Announcement, :count).by(1)
        expect(flash[:notice]).to eq("You've successfully created an announcement for All")
        expect(response).to redirect_to announcements_path
      end

    end

  end

  describe 'update' do

    context 'update' do

      it 'should update the announcement' do
        admin = create(:user, :admin_user)
        session[:user_id] = admin.id
        announcement = create(:announcement, :all)
        patch :update, params: {id: announcement.id, announcement: {public_goal: "volunteer"} }
        expect(response).to redirect_to announcements_path
        expect(Announcement.find(announcement.id).public_goal).to eq("volunteer")
        expect(flash[:notice]).to eq("Announcement updated")
      end

    end

  end

  describe "destroy" do

    context 'destroy' do

      it 'should destroy the announcement' do
        admin = create(:user, :admin_user)
        session[:user_id] = admin.id
        announcement = create(:announcement, :all)
        expect {  delete :destroy, params: {id: announcement.id} }.to change(Announcement, :count).by(-1)
        expect(response).to redirect_to announcements_path
        expect(flash[:notice]).to eq("Announcement Deleted")
      end

    end

  end

end

