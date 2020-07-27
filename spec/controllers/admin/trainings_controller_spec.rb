require 'rails_helper'

RSpec.describe Admin::TrainingsController, type: :controller do
  before(:all) do
    4.times { create(:training) }
    @admin = create(:user, :admin)
    @training = Training.last
  end

  before(:each) do
    session[:user_id] = @admin.id
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@trainings).count).to eq(Training.count)
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
        expect(@controller.instance_variable_get(:@spaces).count).to eq(Space.count)
      end
    end
  end

  describe "GET /edit" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :edit, params: {id: @training.id}
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@spaces).count).to eq(Space.count)
      end
    end
  end

  describe 'POST /create' do
    context 'logged as admin' do
      it 'should create a training and redirect' do
        training_params = FactoryBot.attributes_for(:training)
        expect { post :create, params: {training: training_params} }.to change(Training, :count).by(1)
        expect(flash[:notice]).to eq('Training added successfully!')
        expect(response).to redirect_to admin_trainings_path
      end

      it 'should not create a invalid training' do
        training_params = FactoryBot.attributes_for(:training, name: @training.name)
        expect { post :create, params: {training: training_params} }.to change(Training, :count).by(0)
        expect(flash[:alert]).to eq('Input is invalid')
        expect(response).to redirect_to admin_trainings_path
      end
    end
  end

  describe 'PATCH /update' do
    context 'logged as admin' do
      it 'should not update invalid input for training' do
        first_training = Training.first
        patch :update, params: {id: @training.id, training: {name: first_training.name} }
        expect(response).to redirect_to admin_trainings_path
        expect(Training.find(@training.id).name).to eq(@training.name)
        expect(flash[:alert]).to eq('Input is invalid')
      end

      it 'should update the training' do
        patch :update, params: {id: @training.id, training: {name: "New Random Name"} }
        expect(response).to redirect_to admin_trainings_path
        expect(Training.find(@training.id).name).to eq("New Random Name")
        expect(flash[:notice]).to eq('Training renamed successfully')
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the training' do
        expect { delete :destroy, params: {id: @training.id} }.to change(Training, :count).by(-1)
        expect(@controller.instance_variable_get(:@changed_training)).to eq(@training)
        expect(response).to redirect_to admin_trainings_path
        expect(flash[:notice]).to eq('Training removed successfully')
      end
    end
  end
end

