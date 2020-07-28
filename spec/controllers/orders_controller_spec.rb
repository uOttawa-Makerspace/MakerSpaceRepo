require 'rails_helper'

RSpec.describe OrdersController, type: :controller do

  describe "#index" do

    context "index" do

      before(:each) do
        OrderStatus.create(name: "In progress")
        OrderStatus.create(name: "Completed")
        create(:order, :completed)
        create(:order, :completed)
        create(:order)
      end

      it 'should show the index page for user' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:order, :completed, user_id: user.id)
        create(:order, user_id: user.id)
        get :index
        expect(@controller.instance_variable_get(:@orders).count).to eq(1)
      end

      it 'should show the index page for admins' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:order, :completed, user_id: admin.id)
        create(:order, user_id: admin.id)
        get :index
        expect(@controller.instance_variable_get(:@orders).count).to eq(1)
        expect(@controller.instance_variable_get(:@all_orders).count).to eq(5)
      end

    end

  end

  describe "#create" do

    context "create" do

      before(:each) do
        OrderStatus.create(name: "In progress")
        OrderStatus.create(name: "Completed")
        user = create(:user, :volunteer_with_dev_program)
        create(:order_item, :order_in_progress)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        session[:order_id] = Order.last.id
      end

      it 'should fail creating the order (cc money too low)' do
        post :create
        expect(flash[:alert]).to eq("Not enough Cc Points.")
        expect(response).to have_http_status(302)
      end

      it 'should create the order' do
        CcMoney.create(user_id: User.last.id, cc: 50)
        post :create
        expect(flash[:notice]).to eq('Your Order was successfully processed.')
        expect(session[:order_id]).to be_nil
        expect(response).to redirect_to orders_path
      end

    end

  end

  describe "#destroy" do

    context "destroy" do

      it 'should redirect non-admins to the root_path' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:order)
        delete :destroy, params: {id: Order.last.id}
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq("You can't perform this action")
      end

      it 'should delete the order' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:order, user_id: admin.id)
        expect{ delete :destroy, params: {id: Order.last.id} }.to change(Order, :count).by(-1)
        expect(response).to redirect_to orders_path
        expect(flash[:notice]).to eq('The order was deleted and the CC points returned to the user.')
      end

      it 'should delete the order and all related badges' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        OrderStatus.create(name: "In progress")
        OrderStatus.create(name: "Completed")
        create(:order_item, :awarded_with_badge)
        badge_template_id = OrderItem.last.proficient_project.badge_template.id
        Badge.create(user_id: admin.id, badge_template_id: badge_template_id, acclaim_badge_id: "abc")
        Order.last.update(user_id: admin.id)

        expect{ delete :destroy, params: {id: Order.last.id} }.to change(Order, :count).by(-1)
        expect(Badge.where(user_id: admin.id, badge_template: badge_template_id ).count).to eq(0)
        expect(response).to redirect_to orders_path
        expect(flash[:notice]).to eq('The order was deleted and the CC points returned to the user.')
      end

    end

  end

end




