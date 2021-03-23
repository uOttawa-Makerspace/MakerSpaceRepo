require 'rails_helper'

RSpec.describe DiscountCodesController, type: :controller do
  describe "GET /index" do
    before(:context) do
      @user = create(:user, :regular_user)
      @admin = create(:user, :admin)
      Program.create(user_id: @user.id, program_type: Program::DEV_PROGRAM)
      create(:discount_code, :unused, user: @user)
      create(:discount_code, :unused, user: @admin)
    end

    context 'logged as regular user' do
      it 'should return 200' do
        session[:user_id] = @user.id
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@discount_codes).count).to eq(1)
      end
    end

    context 'logged as admin' do
      it 'should return 200' do
        session[:user_id] = @admin.id
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@all_discount_codes).count).to eq(2)
      end
    end

    after :context do
      DiscountCode.destroy_all
    end
  end

  describe 'Actions' do
    before(:context) do
      @shopify_price_rule_id = PriceRule.create_price_rule("10$ Coupon", 10)
      @price_rule = create(:price_rule, shopify_price_rule_id: @shopify_price_rule_id, value: 10)
      @user = create(:user, :regular_user)
      Program.create(user_id: @user.id, program_type: Program::DEV_PROGRAM)
      CcMoney.create(user_id: @user.id, cc: 1000)
    end

    before(:each) do
      session[:user_id] = @user.id
    end

    context 'GET /new' do
      it 'should return 200' do
        get :new
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@price_rules).count).to eq(3)
      end
    end

    context 'POST /create' do
      it 'should be redirecting to discount code path and creating a discount code' do
        expect { post :create, params: {price_rule_id: @price_rule.id} }.to change(DiscountCode, :count).by(1)
        expect(response).to redirect_to discount_codes_path
        expect(flash[:notice]).to eq('Discount Code created')
      end
    end

    context 'POST /create with expired price rule /check_and_set_price_rule_expiration' do
      it 'should not create a discount code and redirect to new discount code path' do
        price_rule = create(:price_rule, expired_at: DateTime.yesterday)
        expect { post :create, params: {price_rule_id: price_rule.id} }.to change(DiscountCode, :count).by(0)
        expect(response).to redirect_to new_discount_code_path
        expect(flash[:alert]).to eq("This coupon is expired")
      end
    end

    context 'POST /create with no CC points' do
      it 'should fail to create the discount code and redirect to root' do
        CcMoney.create(user_id: @user.id, cc: -1000)
        post :create, params: {price_rule_id: @price_rule.id}
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('Not enough CC points')
      end
    end

    after :context do
      PriceRule.delete_price_rule_from_shopify(@shopify_price_rule_id)
    end
  end
end

