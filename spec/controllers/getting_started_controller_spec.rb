require 'rails_helper'

RSpec.describe GettingStartedController, type: :controller do

  describe "GET /setting_up_account" do

    context "signed in" do

      it 'should give a 200' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :setting_up_account
        expect(response).to have_http_status(:success)
      end

    end

    context "not signed in" do

      it 'should give a 200' do
        get :creating_repository
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "GET /creating_repository" do

    context "signed in" do

      it 'should give a 200' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :creating_repository
        expect(response).to have_http_status(:success)
      end

    end

    context "not signed in" do

      it 'should give a 200' do
        get :creating_repository
        expect(response).to have_http_status(:success)
      end

    end

  end

end



