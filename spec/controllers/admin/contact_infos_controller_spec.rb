require 'rails_helper'

RSpec.describe Admin::ContactInfosController, type: :controller do
  before(:each) do
    @admin = create(:user, :admin)
    session[:user_id] = @admin.id
    @contact1 = create(:contact_info)
    @contact2 = create(:contact_info)
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@contact_infos).count).to eq(2)
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end
  end

  describe 'GET /new' do
    context 'logged as admin' do
      it 'should return a 200' do
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /edit" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :edit, params: {id: @contact1.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /create' do
    context 'logged as admin' do
      it 'should create an contact info and redirect' do
        contact_info_params =  FactoryBot.attributes_for(:contact_info)
        expect { post :create, params: {contact_info: contact_info_params} }.to change(ContactInfo, :count).by(1)
        expect(flash[:notice]).to eq("You've successfully created a new Contact Info !")
        expect(response).to redirect_to admin_contact_infos_path
      end
    end
  end

  describe 'PATCH /update' do
    context 'logged as admin' do
      it 'should update the contact info' do
        patch :update, params: {id: @contact1.id, contact_info: {name: "abc123"} }
        expect(response).to redirect_to admin_contact_infos_path
        expect(ContactInfo.find(@contact1.id).name).to eq("abc123")
        expect(flash[:notice]).to eq("Contact Info updated")
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the contact info' do
        expect { delete :destroy, params: {id: @contact1.id} }.to change(ContactInfo, :count).by(-1)
        expect(response).to redirect_to admin_contact_infos_path
        expect(flash[:notice]).to eq("Contact Info Deleted")
      end
    end
  end

  after(:all) do
    ContactInfo.destroy_all
  end
end



