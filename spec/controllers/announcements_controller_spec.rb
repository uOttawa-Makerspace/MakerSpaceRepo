require 'rails_helper'

RSpec.describe AnnouncementsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @staff = create(:user, :staff)
    @regular_user = create(:user, :regular_user)
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
        expect(@controller.instance_variable_get(:@announcements).count).to eq(1)
      end
    end

    context 'logged as staff' do
      it 'should return 200 response' do
        session[:user_id] = @staff.id
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@announcements).count).to eq(1)
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        session[:user_id] = @regular_user.id
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

    context 'logged as staff' do
      it 'should return 200 response' do
        session[:user_id] = @staff.id
        get :new
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        session[:user_id] = @regular_user.id
        get :new
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  describe "GET /show" do
    context 'logged as admin' do
      it 'should return 200 response' do
        session[:user_id] = @admin.id
        get :show, params: {id: @announcement_volunteer.id}
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as staff' do
      it 'should return 200 response' do
        session[:user_id] = @staff.id
        get :show, params: {id: @announcement_volunteer.id}
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        session[:user_id] = @regular_user.id
        get :show, params: {id: @announcement_volunteer.id}
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  describe "GET /edit" do
    context 'logged as admin' do
      it 'should return 200 response' do
        session[:user_id] = @admin.id
        get :edit, params: {id: @announcement_volunteer.id}
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as staff' do
      it 'should return 200 response' do
        session[:user_id] = @staff.id
        get :edit, params: {id: @announcement_volunteer.id}
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        session[:user_id] = @regular_user.id
        get :edit, params: {id: @announcement_volunteer.id}
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  describe 'POST /create' do
    context 'logged as admin' do
      it 'should create an announcement and redirect' do
        session[:user_id] = @admin.id
        announcement_params =  FactoryBot.attributes_for(:announcement, :volunteer)
        expect { post :create, params: {announcement: announcement_params} }.to change(Announcement, :count).by(1)
        expect(flash[:notice]).to eq("You've successfully created an announcement for Volunteer")
        expect(response).to redirect_to announcements_path
      end
    end

    context 'logged as staff' do
      it 'should return 200 response' do
        session[:user_id] = @staff.id
        announcement_params =  FactoryBot.attributes_for(:announcement, :volunteer)
        expect { post :create, params: {announcement: announcement_params} }.to change(Announcement, :count).by(1)
        expect(flash[:notice]).to eq("You've successfully created an announcement for Volunteer")
        expect(response).to redirect_to announcements_path
      end

      it 'should redirect and not create' do
        session[:user_id] = @staff.id
        announcement_params =  FactoryBot.attributes_for(:announcement, :all)
        expect { post :create, params: {announcement: announcement_params} }.to change(Announcement, :count).by(0)
        expect(flash[:alert]).to eq("Please select another public goal")
        expect(response).to redirect_to new_announcement_path
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        session[:user_id] = @regular_user.id
        announcement_params =  FactoryBot.attributes_for(:announcement, :volunteer)
        expect { post :create, params: {announcement: announcement_params} }.to change(Announcement, :count).by(0)
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  describe 'PATCH /update' do
    context 'logged as admin' do
      it 'should update the announcement' do
        session[:user_id] = @admin.id
        patch :update, params: {id: @announcement_volunteer.id, announcement: {public_goal: "staff"} }
        expect(response).to redirect_to announcements_path
        expect(Announcement.find(@announcement_volunteer.id).public_goal).to eq("staff")
        expect(flash[:notice]).to eq("Announcement updated")
      end
    end

    context 'logged as staff' do
      it 'should return 200 response' do
        session[:user_id] = @staff.id
        patch :update, params: {id: @announcement_volunteer.id, announcement: {public_goal: "staff"} }
        expect(response).to redirect_to announcements_path
        expect(Announcement.find(@announcement_volunteer.id).public_goal).to eq("staff")
        expect(flash[:notice]).to eq("Announcement updated")
      end

      it 'should redirect and not update' do
        session[:user_id] = @staff.id
        patch :update, params: {id: @announcement_admin.id, announcement: {public_goal: "staff"} }
        expect(flash[:alert]).to eq("Please select another public goal")
        expect(response).to redirect_to new_announcement_path
        expect(Announcement.find(@announcement_admin.id).public_goal).to eq("admin")
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        session[:user_id] = @regular_user.id
        patch :update, params: {id: @announcement_volunteer.id, announcement: {public_goal: "staff"} }
        expect(Announcement.find(@announcement_volunteer.id).public_goal).to eq("volunteer")
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the announcement' do
        session[:user_id] = @admin.id
        expect { delete :destroy, params: {id: @announcement_volunteer.id} }.to change(Announcement, :count).by(-1)
        expect(response).to redirect_to announcements_path
        expect(flash[:notice]).to eq("Announcement Deleted")
      end
    end

    context 'logged as staff' do
      it 'should destroy the announcement' do
        session[:user_id] = @staff.id
        expect { delete :destroy, params: {id: @announcement_volunteer.id} }.to change(Announcement, :count).by(-1)
        expect(response).to redirect_to announcements_path
        expect(flash[:notice]).to eq("Announcement Deleted")
      end

      it 'should redirect and not delete' do
        session[:user_id] = @staff.id
        expect { delete :destroy, params: {id: @announcement_all.id} }.to change(Announcement, :count).by(0)
        expect(response).to redirect_to new_announcement_path
        expect(flash[:alert]).to eq("Please select another public goal")
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        session[:user_id] = @regular_user.id
        expect { delete :destroy, params: {id: @announcement_volunteer.id} }.to change(Announcement, :count).by(0)
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  after(:all) do
    Announcement.destroy_all
  end
end

