require 'rails_helper'

RSpec.describe CartsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @order = create(:order, user: @admin)
    4.times { create(:order_item, order: @order) }
  end

  before(:each) do
    session[:user_id] = @admin.id
    session[:order_id] = @order.id
  end

  describe 'GET /index' do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@order_items).count).to eq(4)
      end
    end

    context 'accessing carts' do
      it 'should redirect guests to login' do
        session[:user_id] = nil
        get :index
        expect(response).to redirect_to login_path(back_to: request.path)
      end

      it 'should allow logged in users' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to have_http_status :success
      end
    end
  end

  after(:all) { Order.destroy_all }
end
