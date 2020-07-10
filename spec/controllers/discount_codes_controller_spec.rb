require 'rails_helper'

RSpec.describe DiscountCodesController, type: :controller do
  describe "GET #index" do
    before :context do
      @user = create(:user, :regular_user)
      @admin = create(:user, :admin_user)
      Program.create(user_id: @user.id, program_type: Program::DEV_PROGRAM)
      create(:discount_code, :unused, user: @user)
      create(:discount_code, :unused, user: @admin)
    end

    context 'index' do
      it 'should return 200 with regular user' do
        session[:user_id] = @user.id
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@discount_codes).count).to eq(1)
      end

      it 'should return 200 with admin' do
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
    before :context do
      @shopify_price_rule_id = PriceRule.create_price_rule("10$ Coupon", 10)
      @price_rule = create(:price_rule, shopify_price_rule_id: @shopify_price_rule_id, value: 10)
    end
    context 'GET #new' do
      it 'should be giving a 200' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        get :new
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@price_rules).count).to eq(3)
      end
    end

    context 'POST #create' do
      it 'should be redirecting to discount code path and creating a discount code' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        CcMoney.create(user_id: user.id, cc: 1000)
        expect { post :create, params: {price_rule_id: @price_rule.id} }.to change(DiscountCode, :count).by(1)
        expect(response).to redirect_to discount_codes_path
        expect(flash[:notice]).to eq('Discount Code created')
      end

      it 'should be redirecting to root code path and failing to create the discount code' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
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

