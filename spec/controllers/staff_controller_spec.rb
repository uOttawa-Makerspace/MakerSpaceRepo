require 'rails_helper'

RSpec.describe StaffDashboardController, type: :controller do

  describe "GET /index" do

    context "signed in as regular user" do

      it 'should get redirected to root' do
        user = create(:user, :regular_user)
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end

    end

    context "signed in as admin" do

      it 'should get a 200' do
        admin = create(:user, :admin)
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = admin.id
        expect(response).to have_http_status(:success)
      end

    end

  end


end
