require 'rails_helper'

RSpec.describe QuickAccessLinksController, type: :controller do
  before(:each) do
    @user = create :user, :admin
    session[:user_id] = @user.id
  end

  describe "quick access links" do
    context "accessing links" do
      it "should deny non admins" do
        session[:user_id] = create(:user, :regular_user).id
        post :create, params: attributes_for(:quick_access_link, :root)
        expect(response).not_to have_http_status :success
        expect(response).to redirect_to root_path
      end
      it "should allow admins to access" do
        post :create, params: attributes_for(:quick_access_link, :root)
        expect(response).to have_http_status :success
      end
    end
    context "creating links" do
      it "should create a valid link" do
        post :create, params: attributes_for(:quick_access_link, :root)
        expect(response).to have_http_status :success
      end

      it "should reject invalid links" do
        # The :invalid trait's "admin/invalid" now routes to repositories#show
        # (/:username/:id), which is why this was once disabled; use paths that
        # really fail: no route, and a user's profile page.
        user = create(:user, :regular_user)
        ["/no/such/route/at/all/xyz", "/#{user.username}"].each do |path|
          expect {
            post :create, params: { name: "Bad", path: path }
          }.not_to change(QuickAccessLink, :count)
          expect(response).not_to have_http_status :success
          expect(flash[:alert]).to start_with("Quick access link not created")
        end
        expect(flash[:alert]).to include("cannot point to a user")
      end

      it "should reject duplicate links" do
        post :create, params: attributes_for(:quick_access_link, :root)
        expect(response).to have_http_status :success

        post :create, params: attributes_for(:quick_access_link, :root)
        expect(response).not_to have_http_status :success
        expect(flash[:alert]).not_to be_nil
        expect(QuickAccessLink.where(user_id: @user.id).count).to eq 1
      end
    end
  end
end
