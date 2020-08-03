require 'rails_helper'

RSpec.describe Admin::SpacesController, type: :controller do

  before(:each) do
    @admin = create(:user, :admin)
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @admin.id
  end

  describe 'GET /index' do
    context 'logged as regular user' do
      it 'should return 200' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
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

  describe 'GET /edit' do
    context 'edit page' do
      it 'should return a 200' do
        space = create(:space)
        get :edit, params: {id: space.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /update_name' do
    context 'update name' do
      it 'should return a 200' do
        space = create(:space)
        post :update_name, params: {space_id: space.id, name: "ABC123"}
        expect(response).to have_http_status(302)
        expect(Space.last.name).to eq("ABC123")
      end
    end
  end

  describe 'POST /create' do
    context 'create a space' do
      it 'should create a space' do
        space_params = FactoryBot.attributes_for(:space)
        expect { post :create, params: {space_params: space_params} }.to change(Space, :count).by(1)
        expect(response).to have_http_status(302)
        expect(flash[:notice]).to eq('Space created successfully!')
      end

      it 'should fail creating a space' do
        expect { post :create, params: {space_params: {name: ""}} }.to change(Space, :count).by(0)
        expect(response).to have_http_status(302)
        expect(flash[:alert]).to eq('Something went wrong.')
      end
    end
  end

  describe 'DELETE /destroy' do
    context 'destroy space' do
      it 'should delete the space' do
        space = create(:space)
        expect { delete :destroy, params: {id: space.id, space_id:space.id, admin_input: space.name.upcase} }.to change(Space, :count).by(-1)
        expect(flash[:notice]).to eq('Space deleted!')
        expect(response).to redirect_to admin_spaces_path
      end

      it 'should not delete the space' do
        space = create(:space)
        expect { delete :destroy, params: {id: space.id, space_id:space.id, admin_input: space.name} }.to change(Space, :count).by(0)
        expect(flash[:alert]).to eq('Invalid Input')
        expect(response).to redirect_to admin_spaces_path
      end
    end
  end

end

