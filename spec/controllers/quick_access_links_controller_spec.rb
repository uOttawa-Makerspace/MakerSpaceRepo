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
        # TODO: Disabled because of route.rb respository
        # post :create, params: attributes_for(:quick_access_link, :invalid)
        # expect(response).not_to have_http_status :success
        # expect(flash[:alert]).not_to be_nil
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
