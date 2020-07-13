require 'rails_helper'

RSpec.describe AnnouncementsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @announcement_admin = create(:announcement, :admin)
    @announcement_all = create(:announcement, :all)
    @announcement_volunteer = create(:announcement, :volunteer)
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        session[:user_id] = @admin.id
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@announcements).count).to eq(3)
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  describe 'GET /new' do
    context 'logged as admin' do
      it 'should return a 200' do
        session[:user_id] = @admin.id
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /show" do
    context 'logged as admin' do
      it 'should return 200 response' do
        session[:user_id] = @admin.id
        get :show, params: {id: @announcement_admin.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /edit" do
    context 'logged as admin' do
      it 'should return 200 response' do
        session[:user_id] = @admin.id
        get :edit, params: {id: @announcement_admin.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /create' do
    context 'logged as admin' do
      it 'should create an announcement and redirect' do
        session[:user_id] = @admin.id
        announcement_params =  FactoryBot.attributes_for(:announcement, :all)
        expect { post :create, params: {announcement: announcement_params} }.to change(Announcement, :count).by(1)
        expect(flash[:notice]).to eq("You've successfully created an announcement for All")
        expect(response).to redirect_to announcements_path
      end
    end
  end

  describe 'PATCH /update' do
    context 'logged as admin' do
      it 'should update the announcement' do
        session[:user_id] = @admin.id
        patch :update, params: {id: @announcement_all.id, announcement: {public_goal: "volunteer"} }
        expect(response).to redirect_to announcements_path
        expect(Announcement.find(@announcement_all.id).public_goal).to eq("volunteer")
        expect(flash[:notice]).to eq("Announcement updated")
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the announcement' do
        session[:user_id] = @admin.id
        expect {  delete :destroy, params: {id: @announcement_all.id} }.to change(Announcement, :count).by(-1)
        expect(response).to redirect_to announcements_path
        expect(flash[:notice]).to eq("Announcement Deleted")
      end
    end
  end

  after(:all) do
    Announcement.destroy_all
  end
end

