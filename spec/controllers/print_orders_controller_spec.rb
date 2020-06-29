require 'rails_helper'

RSpec.describe PrintOrdersController, type: :controller do

  describe 'index method' do

    before(:each) do
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
    end

    context 'user' do
      it 'should return a 200' do
        user = create :user, :regular_user
        create(:print_order, :with_file)
        session[:user_id] = user.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'admin' do
      it 'should return a 200' do
        admin = create :user, :admin_user
        create :user, :regular_user
        create(:print_order, :with_file)
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
        print_order_params = FactoryGirl.attributes_for(:print_order, :with_file)
        post :create, params: {print_order: print_order_params}
        expect(response).to redirect_to print_orders_path
        expect(flash[:notice]).to eq('The print order has been sent for admin approval, you will receive an email in the next few days, once the admins made a decision.')
        expect { post :create, params: {print_order: print_order_params} }.to change(PrintOrder, :count).by(1)
      end

      it 'should send an email to makerspace@uottawa.ca' do
        print_order_params = FactoryGirl.attributes_for(:print_order, :with_file)
        post :create, params: {print_order: print_order_params}
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq('makerspace@uottawa.ca')
      end

    end
  end

  describe 'destroy method' do
    context 'destroy print order' do
      it 'should return a 200' do
        user = create :user, :regular_user
        session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
        session[:user_id] = user.id
        create(:print_order, :with_file)
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
        print_order = create(:print_order, :with_file)
        print_order.printed = true
        get :invoice, params: {print_order_id: 1, format: :pdf}
        expect(response).to have_http_status(:success)
      end
    end
  end

end