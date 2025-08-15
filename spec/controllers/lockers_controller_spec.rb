require "rails_helper"

RSpec.describe LockersController, type: :controller do
  describe "GET /index" do
    context "as regular user" do
      it "should deny access" do
        session[:user_id] = create(:user).id
        session[:expires_at] = DateTime.tomorrow.end_of_day
        get :index
        expect(response).to_not have_http_status :success
      end
    end
    context "as staff" do
      it "should allow access" do
        session[:user_id] = create(:user, :staff).id
        session[:expires_at] = DateTime.tomorrow.end_of_day
        get :index
        expect(response).to have_http_status :success
      end
    end

    context "as admin" do
      it "should return success" do
        session[:user_id] = create(:user, :admin).id
        session[:expires_at] = DateTime.tomorrow.end_of_day
        get :index
        expect(response).to have_http_status :success
      end
    end
  end
end
