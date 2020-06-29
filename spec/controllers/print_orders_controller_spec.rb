
require 'rails_helper'

RSpec.describe PrintOrdersController, type: :controller do

  describe 'delete method' do

    before(:each) do
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
    end

    context 'index for user' do
      it 'should return a 200' do
        user = create :user, :regular_user
        create(:print_order, :with_file)
        session[:user_id] = user.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'index for user' do
      it 'should return a 200' do
        admin = create :user, :admin_user
        create :user, :regular_user
        create(:print_order, :with_file)
        session[:user_id] = admin.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

  end

end