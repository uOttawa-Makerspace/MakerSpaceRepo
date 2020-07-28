require 'rails_helper'

RSpec.describe SettingsController, type: :controller do
  before(:all) do
    @user = create(:user, :regular_user)
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @user.id
  end

  describe 'GET /profile' do
    context 'not logged in' do
      it 'should redirect to root' do
        session[:user_id] = ""
        get :profile
        expect(response).to redirect_to login_path
      end
    end

    context 'logged in' do
      it 'should return 200' do
        get :profile
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged in as student' do
      it 'should return 200' do
        user = create(:user, :student)
        session[:user_id] = user.id
        get :profile
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /admin' do

    context 'admin' do
      it 'should show the admin page' do
        get :admin
        expect(response).to have_http_status(:success)
      end
    end

  end

end

