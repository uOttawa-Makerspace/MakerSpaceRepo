require 'rails_helper'

RSpec.describe CartsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @order = create(:order, user: @admin)
    4.times{ create(:order_item, order: @order) }
  end

  before(:each) do
    session[:user_id] = @admin.id
    session[:order_id] = @order.id
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@order_items).count).to eq(4)
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  after(:all) do
    Order.destroy_all
  end
end

