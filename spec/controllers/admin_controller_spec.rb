require 'rails_helper'

RSpec.describe AdminController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
  end

  before(:each) do
    session[:user_id] = @admin.id
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as regular user' do
      it 'should not be able to access this page /ensure_admin' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "GET /manage_badges" do
    context "logged as admin" do
      it 'should update badges' do
        get :manage_badges, params: { refresh: "badges" }
        expect(flash[:notice]).to eq('Badges Update is now complete!')
      end

      it 'should update badge templates' do
        get :manage_badges, params: { refresh: "templates" }
        expect(flash[:notice]).to eq('Badge Templates Update is now complete!')
      end
    end
  end
end




