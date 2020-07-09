require 'rails_helper'

RSpec.describe PriceRulesController, type: :controller do

  describe 'admin access' do

    context 'check if user redirected' do

      it 'should redirect the user to root' do
        user = create :user, :regular_user
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')

      end

      it 'should leave the admin to the price rule path' do
        admin = create :user, :admin_user
        session[:user_id] = admin.id
        get :index
        expect(response).to have_http_status(:success)
      end

    end
  end

  describe 'edit' do
    context 'edit' do
      it 'should return a 200' do
        admin = create :user, :admin_user
        session[:user_id] = admin.id
        price_rule = create(:price_rule)
        get :edit, params: {id: price_rule.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'new' do

    context 'new' do

      it 'should return a 200' do
        admin = create :user, :admin_user
        session[:user_id] = admin.id
        get :new
        expect(response).to have_http_status(:success)
      end

    end
  end

  describe 'create method' do

    before(:each) do
      admin = create :user, :admin_user
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
      session[:user_id] = admin.id
    end

    context 'create price rule' do

      it 'should create a price rule' do
        price_rule_params = FactoryBot.attributes_for(:price_rule, shopify_price_rule_id: nil)
        post :create, params: {price_rule: price_rule_params}
        expect(response).to redirect_to price_rules_path
        expect(flash[:notice]).to eq('Price rule was successfully created.')
        expect { post :create, params: {price_rule: price_rule_params} }.to change(PriceRule, :count).by(1)
      end

      it 'should redirect to new' do
        price_rule_params = FactoryBot.attributes_for(:price_rule, shopify_price_rule_id: nil)
        post :create, params: {price_rule: price_rule_params}
        expect(response).to have_http_status(302)
      end

    end
  end

  describe 'update method' do

    before(:each) do
      admin = create :user, :admin_user
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
      session[:user_id] = admin.id
    end

    context 'update price rule' do

      it 'should create a price rule' do
        price_rule_params = FactoryBot.attributes_for(:price_rule, shopify_price_rule_id: nil)
        post :create, params: {price_rule: price_rule_params}
        patch :update, params: {id: PriceRule.last.id, price_rule: {title: "6$ coupon", value: 6, cc: 60}}
        expect(response).to redirect_to price_rules_path
        expect(flash[:notice]).to eq('Price rule was successfully updated.')
      end

      it 'should redirect to edit' do
        price_rule_params = FactoryBot.attributes_for(:price_rule, shopify_price_rule_id: nil)
        post :create, params: {price_rule: price_rule_params}
        patch :update, params: {id: PriceRule.last.id, price_rule: {titled: "6$ coupon", cc: "asfa"}}
        expect(response).to have_http_status(302)
      end

    end
  end

  describe 'destroy method' do

    before(:each) do
      admin = create :user, :admin_user
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
      session[:user_id] = admin.id
    end

    context 'destroy price rule' do

      it 'should destroy a price rule' do
        price_rule_params = FactoryBot.attributes_for(:price_rule, shopify_price_rule_id: nil)
        post :create, params: {price_rule: price_rule_params}
        expect { delete :destroy, params: {id: PriceRule.last.id} }.to change(PriceRule, :count).by(-1)
        expect(response).to redirect_to price_rules_path
        expect(flash[:notice]).to eq('Price rule was successfully destroyed.')
      end
    end
  end

  describe 'check discount codes method' do

    before(:each) do
      admin = create :user, :admin_user
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
      session[:user_id] = admin.id
    end

    context 'check discount codes price rule' do

      it 'check discount codes price rule with delete' do
        price_rule_params = FactoryBot.attributes_for(:price_rule)
        post :create, params: {price_rule: price_rule_params}
        create(:discount_code, user_id: session[:user_id], shopify_discount_code_id: PriceRule.last.shopify_price_rule_id, price_rule_id: PriceRule.last.id)
        patch :update, params: {id: PriceRule.last.id, price_rule: {title: "6$ coupon", value: 6, cc: 60}}
        expect(response).to redirect_to price_rules_path
        expect(flash[:alert]).to eq('This price rule cannot be edited/deleted because it has already discount codes')
      end

    end
  end


end
