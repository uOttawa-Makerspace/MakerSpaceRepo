require 'rails_helper'

RSpec.describe DiscountCodesController, type: :controller do

  describe "index" do

    context 'index' do

      it 'should be giving a 200 with regular user' do
        user = create(:user, :regular_user)
        admin = create(:user, :admin_user)
        session[:user_id] = user.id
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        create(:discount_code, :unused, user: user)
        create(:discount_code, :unused, user: admin)
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@discount_codes).count).to eq(1)
      end

      it 'should be giving a 200 with admin' do
        admin = create(:user, :admin_user)
        user = create(:user, :regular_user)
        session[:user_id] = admin.id
        create(:discount_code, :unused, user: admin)
        create(:discount_code, :unused, user: user)
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@all_discount_codes).count).to eq(2)
      end

    end

  end

  describe 'new method' do

    context 'new' do

      it 'should be giving a 200' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        create(:price_rule)
        create(:price_rule)
        get :new
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@price_rules).count).to eq(2)
      end

    end

  end

  describe 'create method' do

    context 'create' do

      it 'should be redirecting to discount code path and creating a discount code' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        CcMoney.create(user_id: user.id, cc: 1000)

        price_rule_shopify_id = PriceRule.create_price_rule("5$ Coupon", 5)
        create(:price_rule, shopify_price_rule_id: price_rule_shopify_id, title: "5$ Coupon", value: 5)

        expect { post :create, params: {price_rule_id: PriceRule.last.id} }.to change(DiscountCode, :count).by(1)
        expect(response).to redirect_to discount_codes_path
        expect(flash[:notice]).to eq('Discount Code created')
      end

      it 'should be redirecting to root code path and failing to create the discount code' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)

        price_rule_shopify_id = PriceRule.create_price_rule("5$ Coupon", 5)
        create(:price_rule, shopify_price_rule_id: price_rule_shopify_id, title: "5$ Coupon", value: 5)

        post :create, params: {price_rule_id: PriceRule.last.id}
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('Not enough CC points')
      end
    end

  end

end

