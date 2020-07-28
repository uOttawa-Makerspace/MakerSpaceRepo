require 'rails_helper'
include FilesTestHelper

RSpec.describe SessionsController, type: :controller do

  describe "POST /login_authentication" do

    context "login_authentication" do

      before(:all) do
        @user = create(:user, :regular_user)
      end

      it 'should login the user' do
        post :login_authentication, params: {username_email: @user.username, password: 'asa32A353#'}
        expect(response).to redirect_to root_path
      end

      it 'should not login the user with a wrong password' do
        post :login_authentication, params: {username_email: @user.username, password: 'abc123'}
        expect(response).to have_http_status(200)
        expect(flash[:alert]).to eq('Incorrect username or password.')
      end

    end

  end

  describe "GET /login" do

    context "login" do

      before(:all) do
        @user = create(:user, :regular_user)
      end

      it 'should login the user' do
        get :login
        expect(response).to have_http_status(:success)
      end

      it 'should not login the user that is already logged in' do
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = @user.id
        get :login
        expect(flash[:alert]).to eq('You are already logged in.')
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "GET /logout" do

    context "logout" do

      it 'should log out the user' do
        user = create(:user, :regular_user)
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
        get :logout
        expect(response).to redirect_to root_path
      end

    end

  end
  
end

