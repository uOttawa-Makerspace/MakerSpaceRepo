require "rails_helper"

RSpec.describe BadgesController, type: :controller do
  before(:each) do
    OrderStatus.find_by!(name: "In progress")
    OrderStatus.find_by!(name: "Completed")
  end

  describe "#index" do
    context "index" do
      it "should show the index page" do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        get :index
        expect(response).to have_http_status(:success)
      end

      it "should show the index page (admin)" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        get :index
        expect(response).to have_http_status(:success)
      end

      it "should show the index page when using js" do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        get :index, format: "js", xhr: true
        expect(response).to have_http_status(:success)
      end

      it "should prevent unauthenticated users" do
        session[:user_id] = nil
        get :index
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "#show" do
    context "show" do
      it "should allow non-authenticated" do
        session[:user_id] = nil
        badge = create(:certification)
        expect(get(:show, params: {id: badge.id})).to have_http_status(:success)
      end

      it "should allow authenticated users" do
        user = create(:user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        badge = create(:certification)
        expect(get(:show, params: {id: badge.id})).to have_http_status(:success)
      end
    end
  end
end