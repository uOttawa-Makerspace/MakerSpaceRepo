require 'rails_helper'

RSpec.describe Admin::DropOffLocationsController, type: :controller do
  before(:each) do
    @admin = create(:user, :admin)
    session[:user_id] = @admin.id
    @location1 = create(:drop_off_location)
    @location2 = create(:drop_off_location)
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@locations).count).to eq(2)
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
        get :edit, params: {id: @location1.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /create' do
    context 'logged as admin' do
      it 'should create an drop-off location and redirect' do
        drop_off_locations_params =  FactoryBot.attributes_for(:drop_off_location)
        expect { post :create, params: {drop_off_location: drop_off_locations_params} }.to change(DropOffLocation, :count).by(1)
        expect(flash[:notice]).to eq('Drop-off Location added successfully!')
        expect(response).to redirect_to admin_drop_off_locations_path
      end
    end
  end

  describe 'PATCH /update' do
    context 'logged as admin' do
      it 'should update the drop-off location' do
        patch :update, params: {id: @location1.id, drop_off_location: {name: "abc123"} }
        expect(response).to redirect_to admin_drop_off_locations_path
        expect(DropOffLocation.find(@location1.id).name).to eq("abc123")
        expect(flash[:notice]).to eq('Drop-off Location renamed successfully')
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the drop-off location' do
        expect { delete :destroy, params: {id: @location1.id} }.to change(DropOffLocation, :count).by(-1)
        expect(response).to redirect_to admin_drop_off_locations_path
        expect(flash[:notice]).to eq('Drop-off Location Deleted successfully')
      end
    end
  end

  after(:all) do
    DropOffLocation.destroy_all
  end
end



