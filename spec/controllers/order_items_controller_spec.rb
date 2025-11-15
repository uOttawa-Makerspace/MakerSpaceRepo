require "rails_helper"

RSpec.describe OrderItemsController, type: :controller do
  before(:all) do
    @volunteer = create(:user, :volunteer_with_dev_program)
    OrderStatus.find_by!(name: "In progress")
    OrderStatus.find_by!(name: "Completed")
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @volunteer.id
  end

  describe "POST /create" do
    context "logged as regular user" do
      it "should not let regular user to create order item" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        pp = create(:proficient_project)
        expect do
          post :create,
               params: {
                 order_item: {
                   proficient_project_id: pp.id,
                   quantity: 1
                 }
               }
        end.to change(OrderItem, :count).by(0)
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq("You must be a part of the Development Program to access this area.")
      end
    end

    context "logged as volunteer user" do
      it "should create an order item" do
        pp = create(:proficient_project)
        expect do
          post :create,
               params: {
                 order_item: {
                   proficient_project_id: pp.id,
                   quantity: 1
                 },
                 format: "js"
               }
        end.to change(OrderItem, :count).by(1)
        expect(response).to redirect_to carts_path
        expect(session[:order_id]).to eq(Order.last.id)
      end

      it "should create an order item with training requirements" do
        # Make a proficient project with training requirements
        pp = create(:proficient_project, :with_training_requirements)
        # give the user the certifications needed for each requirement
        pp.training_requirements.each do |training_requirement|
          training_session = create(:training_session, training_id: training_requirement.training_id, 
level: training_requirement.level)
          create(:certification, user_id: @volunteer.id, training_session_id: training_session.id, 
level: training_session.level)
        end
        # Make a request
        expect do
          post :create,
               params: {
                 order_item: {
                   proficient_project_id: pp.id,
                   quantity: 1
                 }
               }
        end.to change(OrderItem, :count).by(1)
        expect(response).to redirect_to carts_path
        expect(session[:order_id]).to eq(Order.last.id)
      end
    end
  end

  describe "PATCH /update" do
    context "logged as volunteer user" do
      it "should update an order item" do
        create(:order_item)
        session[:order_id] = Order.last.id
        patch :update,
              params: {
                id: OrderItem.last.id,
                order_item: {
                  quantity: 2
                },
                format: "js"
              }
        expect(response).to have_http_status(:success)
        expect(OrderItem.last.quantity).to eq(2)
      end
    end
  end

  describe "DELETE /destroy" do
    context "destroy the order item" do
      it "should delete the order item" do
        create(:order_item)
        session[:order_id] = Order.last.id
        expect do
          delete :destroy, params: { order_item_id: OrderItem.last.id }, format: "js"
        end.to change(OrderItem, :count).by(-1)
        expect(flash[:notice]).to eq("Successfully removed item from cart")
        expect(response).to redirect_to carts_path
      end
    end
  end
end
