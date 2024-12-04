require "rails_helper"

RSpec.describe KioskController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @staff = create(:user, :staff)
    @user = create(:user, :regular_user)
    @space = create(:space)
  end

  describe "GET /index" do
    context "logged as admin" do
      it "should return 200 response" do
        admin = create :user, :admin
        session[:user_id] = admin.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as staff" do
      it "should return 200 response" do
        session[:user_id] = @staff.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as regular user" do
      it "should redirect to root path" do
        session[:user_id] = @user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "GET /show as staff" do
    it "should return success" do
      session[:user_id] = @staff.id
      get :show, params: { id: @space.id }
      expect(response).to have_http_status(:success)
    end
  end

  describe "Sign in user to Makerspace kiosk" do
    last_sign_out_time = nil
    it "should sign in and out user" do
      session[:user_id] = @staff.id
      # once with username, other with email
      post :sign_email,
           params: {
             kiosk_id: @space.id,
             visitor: @user.username,
             entering: "true"
           }
      expect(flash[:notice]).to_not be_nil
      expect(flash[:alert]).to be_nil
      expect(response).to redirect_to kiosk_path(@space.id)
      # test for lab session
      expect(LabSession.last.user.id).to eq(@user.id)
      expect(LabSession.last.space.id).to eq(@space.id)
      last_sign_out_time = LabSession.last.sign_out_time
      # sign out user
      post :sign_email,
           params: {
             kiosk_id: @space.id,
             visitor: @user.email,
             leaving: "true"
           }
      expect(flash[:notice]).to_not be_nil
      expect(flash[:alert]).to be_nil
      expect(response).to redirect_to kiosk_path(@space.id)

      expect(LabSession.last.sign_out_time).to be < last_sign_out_time
    end
  end
end
