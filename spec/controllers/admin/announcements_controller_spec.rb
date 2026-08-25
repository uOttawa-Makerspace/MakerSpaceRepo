require "rails_helper"

RSpec.describe Admin::AnnouncementsController, type: :controller do
  let(:admin) { create(:user, :admin) }
  let!(:announcement_admin) { create(:announcement, :admin, user: admin) }
  let!(:announcement_all) { create(:announcement, :all, user: admin) }
  let!(:announcement_volunteer) { create(:announcement, :volunteer, user: admin) }

  before(:each) do
    session[:expires_at] = Time.zone.now + 10_000
  end

  describe "GET /index" do
    context "logged as admin" do
      it "should return 200 response" do
        session[:user_id] = admin.id
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@announcements).count).to eq(3)
      end
    end

    context "logged as regular user" do
      it "should redirect user to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "GET /new" do
    context "logged as admin" do
      it "should return a 200" do
        session[:user_id] = admin.id
        get :new
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as regular user" do
      it "should redirect user to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :new
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "GET /show" do
    context "logged as admin" do
      it "should return 200 response" do
        session[:user_id] = admin.id
        get :show, params: { id: announcement_admin.id }
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as regular user" do
      it "should redirect user to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :show, params: { id: announcement_admin.id }
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "GET /edit" do
    context "logged as admin" do
      it "should return 200 response" do
        session[:user_id] = admin.id
        get :edit, params: { id: announcement_admin.id }
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as regular user" do
      it "should redirect user to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :edit, params: { id: announcement_admin.id }
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "POST /create" do
    context "logged as admin" do
      it "should create an announcement and redirect" do
        session[:user_id] = admin.id
        announcement_params = attributes_for(:announcement, :all)
        expect do
          post :create, params: { announcement: announcement_params }
        end.to change(Announcement, :count).by(1)
        expect(response).to redirect_to admin_announcements_path
        expect(flash[:notice]).to eq("You've successfully created an announcement for All")
      end
    end

    context "logged as regular user" do
      it "should redirect user to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        announcement_params = attributes_for(:announcement, :all)
        post :create, params: { announcement: announcement_params }
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "PATCH /update" do
    context "logged as admin" do
      it "should update the announcement" do
        session[:user_id] = admin.id
        patch :update, params: { id: announcement_admin.id, announcement: { description: "Updated" } }
        expect(response).to redirect_to admin_announcements_path
        expect(flash[:notice]).to eq("Announcement updated")
      end
    end

    context "logged as regular user" do
      it "should redirect user to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        patch :update, params: { id: announcement_admin.id, announcement: { description: "Updated" } }
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "DELETE /destroy" do
    context "logged as admin" do
      it "should destroy the announcement" do
        session[:user_id] = admin.id
        expect do
          delete :destroy, params: { id: announcement_admin.id }
        end.to change(Announcement, :count).by(-1)
        expect(response).to redirect_to admin_announcements_path
        expect(flash[:notice]).to eq("Announcement Deleted")
      end
    end

    context "logged as regular user" do
      it "should redirect user to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        delete :destroy, params: { id: announcement_admin.id }
        expect(response).to redirect_to root_path
      end
    end
  end
end
