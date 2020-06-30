require 'rails_helper'

RSpec.describe PrintOrdersController, type: :controller do

  describe 'index method' do

    before(:each) do
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
    end

    context 'user' do
      it 'should return a 200' do
        user = create :user, :regular_user
        create(:print_order, :working_print_order)
        session[:user_id] = user.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'admin' do
      it 'should return a 200' do
        admin = create :user, :admin_user
        create :user, :regular_user
        create(:print_order, :working_print_order)
        session[:user_id] = admin.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'new method' do

    before(:each) do
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
    end

    context 'new' do
      it 'should return a 200' do
        user = create :user, :regular_user
        session[:user_id] = user.id
        get :new
        expect(response).to have_http_status(:success)
      end
    end

    context 'pricing' do
      it 'should return a return internal pricing of 0.15' do
        user = create :user, :student
        session[:user_id] = user.id
        get :new
        expect(@controller.instance_variable_get(:@table)[0]).to eq(['3D Low (PLA/ABS), (per g)', 0.15, 15])
      end

      it 'should return a return external pricing of 0.3' do
        user = create :user, :regular_user
        session[:user_id] = user.id
        get :new
        expect(@controller.instance_variable_get(:@table)[0]).to eq(['3D Low (PLA/ABS), (per g)', 0.3, 15])
      end
    end
  end

  describe 'create method' do

    before(:each) do
      user = create :user, :regular_user
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
      session[:user_id] = user.id
    end

    context 'create print order' do
      it 'should create a print order with notice' do
        print_order_params = FactoryGirl.attributes_for(:print_order, :working_print_order)
        post :create, params: {print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(flash[:notice]).to eq('The print order has been sent for admin approval, you will receive an email in the next few days, once the admins made a decision.')
        expect { post :create, params: {print_order: print_order_params} }.to change(PrintOrder, :count).by(1)
      end

      it 'should send an email to makerspace@uottawa.ca' do
        print_order_params = FactoryGirl.attributes_for(:print_order, :working_print_order)
        post :create, params: {print_order: print_order_params}
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq('makerspace@uottawa.ca')
      end

      it 'should fail creating the print order' do
        print_order_params = FactoryGirl.attributes_for(:print_order, :broken_print_order)
        post :create, params: {print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(flash[:alert]).to eq('The upload as failed ! Make sure the file types are STL for 3D Printing or SVG and PDF for Laser Cutting !')
        expect { post :create, params: {print_order: print_order_params} }.to change(PrintOrder, :count).by(0)
      end

    end
  end


  describe 'update method' do

    before(:each) do
      user = create :user, :regular_user
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
      session[:user_id] = user.id
    end

    context 'Update print order to approved' do
      it 'should update the print order and send the quote' do
        create(:print_order, :working_print_order)
        print_order_params = FactoryGirl.attributes_for(:print_order, :approved_print_order)
        patch :update, params: {id: 1, print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(PrintOrder.find(1).quote).to eq(70)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq(User.find(1).email)
      end
    end

    context 'Update print order to disapproved' do
      it 'should update the print order to disapproved and send an email' do
        create(:print_order, :working_print_order)
        print_order_params = FactoryGirl.attributes_for(:print_order, :disapproved_print_order)
        patch :update, params: {id: 1, print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(PrintOrder.find(1).approved?).to eq(false)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq(User.find(1).email)
      end
    end

    context 'User approves print order' do
      it 'should update the print order to user_approval = true' do
        create(:print_order, :working_print_order)
        print_order_params = FactoryGirl.attributes_for(:print_order, :user_approved_print_order)
        patch :update, params: {id: 1, print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(PrintOrder.find(1).user_approval?).to eq(true)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq("makerspace@uottawa.ca")
      end
    end

    context 'Print order printed' do
      it 'should update the print order to printed = true and send emails' do
        create(:print_order, :working_print_order)
        print_order_params = FactoryGirl.attributes_for(:print_order, :printed_print_order)
        patch :update, params: {id: 1, print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(PrintOrder.find(1).printed?).to eq(true)
        expect(ActionMailer::Base.deliveries.count).to eq(2)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq(User.find(1).email)
        expect(ActionMailer::Base.deliveries.second.to.first).to eq("uomakerspaceprintinvoices@gmail.com")

      end
    end
  end

  describe 'destroy method' do
    context 'destroy print order' do
      it 'should return a 200' do
        user = create :user, :regular_user
        session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
        session[:user_id] = user.id
        create(:print_order, :working_print_order)
        expect { delete :destroy, params: {id: 1} }.to change(PrintOrder, :count).by(-1)
        expect(response).to redirect_to print_orders_path
      end
    end
  end

  describe 'invoice method' do
    context 'create an invoice for print order' do

      it 'should return render a pdf' do
        user = create :user, :regular_user
        session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
        session[:user_id] = user.id
        print_order = create(:print_order, :working_print_order)
        print_order.printed = true
        get :invoice, params: {print_order_id: 1, format: :pdf}
        expect(response).to have_http_status(:success)
      end

    end
  end

end