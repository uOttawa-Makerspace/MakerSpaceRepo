require 'rails_helper'
include FilesTestHelper

RSpec.describe PrintOrdersController, type: :controller do
  before(:all) do
    @user = create(:user, :regular_user)
    @admin = create(:user, :admin)
    @student = create(:user, :student)
    @print_order = create(:print_order)
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @user.id
  end

  describe 'GET /index' do
    context 'logged as regular user' do
      it 'should return 200' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as admin' do
      it 'should return 200' do
        session[:user_id] = @admin.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /new' do
    context 'logged as regular user' do
      it 'should return a 200' do
        get :new
        expect(response).to have_http_status(:success)
      end
    end

    context 'pricing values' do
      it 'should return a return internal pricing of 0.15' do
        session[:user_id] = @student.id
        get :new
        expect(@controller.instance_variable_get(:@table)[0]).to eq(['3D Low (PLA/ABS), (per g)', 0.15, 15])
      end

      it 'should return a return external pricing of 0.3' do
        get :new
        expect(@controller.instance_variable_get(:@table)[0]).to eq(['3D Low (PLA/ABS), (per g)', 0.3, 15])
      end
    end
  end

  describe 'POST /create' do
    context 'create print order' do
      it 'should create a print order with notice' do
        print_order_params = FactoryBot.attributes_for(:print_order)
        post :create, params: {print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(flash[:notice]).to eq('The print order has been sent for admin approval, you will receive an email in the next few days, once the admins made a decision.')
        expect { post :create, params: {print_order: print_order_params} }.to change(PrintOrder, :count).by(1)
      end

      it 'should send an email to makerspace@uottawa.ca' do
        print_order_params = FactoryBot.attributes_for(:print_order)
        post :create, params: {print_order: print_order_params}
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq('makerspace@uottawa.ca')
      end

      it 'should fail creating the print order' do
        print_order_params = FactoryBot.attributes_for(:print_order, :with_invalid_file)
        post :create, params: {print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(flash[:alert]).to eq('The upload as failed ! Make sure the file types are STL for 3D Printing or SVG and PDF for Laser Cutting !')
        expect { post :create, params: {print_order: print_order_params} }.to change(PrintOrder, :count).by(0)
      end
    end
  end

  describe 'PATCH #update' do
    context 'Update print order to approved' do
      it 'should update the print order and send the quote' do
        print_order = create(:print_order, :with_file)
        print_order_params = FactoryBot.attributes_for(:print_order, :approved)
        patch :update, params: {id: print_order.id, print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(PrintOrder.find(print_order.id).quote).to eq(70)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq(print_order.user.email)
      end
    end

    context 'Update print order to disapproved' do
      it 'should update the print order to disapproved and send an email' do
        print_order = create(:print_order, :with_file)
        print_order_params = FactoryBot.attributes_for(:print_order, :disapproved)
        patch :update, params: {id: print_order.id, print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(PrintOrder.find(print_order.id).approved?).to eq(false)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq(print_order.user.email)
      end
    end

    context 'User approves print order' do
      it 'should update the print order to user_approval = true' do
        print_order = create(:print_order, :with_file)
        print_order_params = { user_approval: true }
        patch :update, params: {id: print_order.id, print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(PrintOrder.find(print_order.id).user_approval?).to eq(true)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq("makerspace@uottawa.ca")
      end
    end

    context 'Print order printed' do
      it 'should update the print order to printed = true and send emails' do
        print_order = create(:print_order, :with_file, :user_approved)
        print_order_params = { printed: true }
        patch :update, params: {id: print_order.id, print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(PrintOrder.find(print_order.id).printed?).to eq(true)
        expect(ActionMailer::Base.deliveries.count).to eq(2)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq(print_order.user.email)
        expect(ActionMailer::Base.deliveries.second.to.first).to eq("uomakerspaceprintinvoices@gmail.com")
      end
    end
  end

  describe 'DELETE /destroy' do
    context 'destroy print order' do
      it 'should return a 200' do
        print_order = create(:print_order)
        expect { delete :destroy, params: {id: print_order.id} }.to change(PrintOrder, :count).by(-1)
        expect(response).to redirect_to print_orders_path
      end
    end
  end

  describe 'GET /invoice' do
    context 'create an invoice for print order' do
      it 'should return render a pdf' do
        print_order = create(:print_order)
        print_order.printed = true
        get :invoice, params: {print_order_id: print_order.id, format: :pdf}
        expect(response).to have_http_status(:success)
      end
    end
  end
end
