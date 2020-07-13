require 'rails_helper'

RSpec.describe PriceRulesController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @user = create(:user, :regular_user)
    @shopify_price_rule_id = PriceRule.create_price_rule("2$ Coupon", 2)
    @price_rule = create(:price_rule, shopify_price_rule_id: @shopify_price_rule_id)
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @admin.id
  end

  describe 'before_action :admin_access' do
    context 'check if user is admin' do
      it 'should redirect to root' do
        session[:user_id] = @user.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end

      it 'should leave the admin to the price rule path' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /new' do
    context 'admin should be able to access new page' do
      it 'should return 200' do
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /edit' do
    context 'admin should be able to access edit page' do
      it 'should return 200' do
        get :edit, params: {id: @price_rule.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /create' do
    context 'create price rule' do
      it 'should create a price rule' do
        price_rule_params = FactoryBot.attributes_for(:price_rule, shopify_price_rule_id: nil)
        post :create, params: {price_rule: price_rule_params}
        expect(response).to redirect_to price_rules_path
        expect(flash[:notice]).to eq('Price rule was successfully created.')
        expect { post :create, params: {price_rule: price_rule_params} }.to change(PriceRule, :count).by(1)
      end

      it 'should redirect to new path' do
        price_rule_params = FactoryBot.attributes_for(:price_rule, shopify_price_rule_id: nil)
        post :create, params: {price_rule: price_rule_params}
        expect(response).to have_http_status(302)
      end
    end
  end

  describe '#check_discount_codes' do
    context "price rules with discount codes can't be updated" do
      it 'should not update the price rule' do
        price_rule_with_discount_codes = create(:price_rule_with_discount_codes)
        patch :update, params: {id: price_rule_with_discount_codes.id, price_rule: {title: "8$ coupon", value: 8, cc: 80}}
        expect(PriceRule.find(price_rule_with_discount_codes.id).title).to eq("5$ coupon")
        expect(response).to redirect_to price_rules_path
        expect(flash[:alert]).to eq('This price rule cannot be edited/deleted because it has already discount codes')
      end
    end
  end

  describe 'PATCH /update' do
    context 'update price rule' do
      it 'should update a price rule' do
        patch :update, params: {id: @price_rule.id, price_rule: {title: "6.2$ coupon", value: 6, cc: 60}}
        expect(PriceRule.find(@price_rule.id).title).to eq("6.2$ coupon")
        expect(response).to redirect_to price_rules_path
        expect(flash[:notice]).to eq('Price rule was successfully updated.')
      end
    end
  end

  describe 'DELETE /destroy' do
    context 'destroy price rule' do
      it 'should destroy a price rule' do
        expect { delete :destroy, params: {id: @price_rule.id} }.to change(PriceRule, :count).by(-1)
        expect(response).to redirect_to price_rules_path
        expect(flash[:notice]).to eq('Price rule was successfully destroyed.')
      end
    end
  end
end
