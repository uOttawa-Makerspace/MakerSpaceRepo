require 'rails_helper'

RSpec.describe OrderItemsController, type: :controller do
  before(:all) do
    @volunteer = create(:user, :volunteer_with_dev_program)
    OrderStatus.create(id: 1, name: 'In progress')
    OrderStatus.create(id: 2, name: 'Completed')
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @volunteer.id
  end

  describe 'POST /create' do
    context 'logged as regular user' do
      it 'should create an order item' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        pp = create(:proficient_project)
        expect{ post :create, params: {order_item: {proficient_project_id: pp.id, quantity: 1}} }.to change(OrderItem, :count).by(0)
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end

    context 'logged as volunteer user' do

      it 'should create an order item' do
        pp = create(:proficient_project)
        expect{ post :create, params: {order_item: {proficient_project_id: pp.id, quantity: 1}, format: "js"} }.to change(OrderItem, :count).by(1)
        expect(response).to have_http_status(:success)
        expect(session[:order_id]).to eq(Order.last.id)
      end

      it 'should create an order item with badge requirements' do
        pp = create(:proficient_project, :with_badge_requirements)
        Badge.create(user_id: User.last.id, badge_template_id: (BadgeTemplate.find_by_badge_name('Beginner - 3D printing || Débutant - Impression 3D').id), acclaim_badge_id: "abcd")
        Badge.create(user_id: User.last.id, badge_template_id: BadgeTemplate.find_by_badge_name('Beginner Laser cutting || Beginner - Laser cutting').id, acclaim_badge_id: "abce")
        expect{ post :create, params: {order_item: {proficient_project_id: pp.id, quantity: 1}, format: "js"} }.to change(OrderItem, :count).by(1)
        expect(response).to have_http_status(:success)
        expect(session[:order_id]).to eq(Order.last.id)
      end

    end
  end

  describe 'PATCH /update' do
    context 'logged as volunteer user' do

      it 'should update an order item' do
        create(:order_item)
        session[:order_id] = Order.last.id
        patch :update, params: {id: OrderItem.last.id, order_item: {quantity: 2}, format: "js"}
        expect(response).to have_http_status(:success)
        expect(OrderItem.last.quantity).to eq(2)
      end

    end
  end

  describe 'DELETE /destroy' do
    context 'destroy the order item' do
      it 'should delete the order item' do
        create(:order_item)
        session[:order_id] = Order.last.id
        expect{ delete :destroy, params: {id: OrderItem.last.id}, format: "js" }.to change(OrderItem, :count).by(-1)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /revoke' do
    context 'revoke the order item' do
      it 'should revoke the order item' do
        create(:order_item)
        session[:order_id] = Order.last.id
        get :revoke, params: {order_item_id: OrderItem.last.id}, format: "js"
        expect(response).to have_http_status(:success)
        expect(OrderItem.last.status).to eq("Revoked")
      end
    end
  end

end


