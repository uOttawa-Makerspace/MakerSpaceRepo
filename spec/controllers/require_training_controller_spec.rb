require 'rails_helper'

RSpec.describe RequireTrainingsController, type: :controller do

  describe "POST /create" do

    context "create required training" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        @task = create(:volunteer_task)
      end

      it 'should create the requirement' do
        training = create(:training)
        expect{ post :create, params: {require_training: {training_id: training.id, volunteer_task: @task.id} } }.to change(RequireTraining, :count).by(1)
        expect(flash[:notice]).to eq("You've successfully added a required training for this volunteer task.")
        expect(response).to have_http_status(302)
      end

      it 'should fail creating the requirement' do
        expect{ post :create, params: {require_training: {training_id: "", volunteer_task: @task.id} } }.to change(RequireTraining, :count).by(0)
        expect(flash[:notice]).to eq('Something went wrong')
        expect(response).to have_http_status(:success)
      end

      it 'should create the requirement (not admin)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        require_trainings_params = FactoryBot.attributes_for(:require_training)
        expect{ post :create, params: {require_training: require_trainings_params} }.to change(RequireTraining, :count).by(0)
        expect(flash[:alert]).to eq("You cannot access this area.")
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "POST /remove_trainings" do

    context "create required training" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        @require_training = create(:require_training)
      end

      it 'should create the requirement' do
        expect{ post :remove_trainings, params: {require_training: {training_id: @require_training.training_id, volunteer_task: @require_training.volunteer_task_id} } }.to change(RequireTraining, :count).by(-1)
        expect(flash[:notice]).to eq("You've successfully deleted this required training")
        expect(response).to have_http_status(302)
      end

      it 'should fail creating the requirement' do
        expect{ post :remove_trainings, params: {require_training: {training_id: "", volunteer_task: @require_training.volunteer_task_id} } }.to change(RequireTraining, :count).by(0)
        expect(flash[:alert]).to eq('Something went wrong')
        expect(response).to have_http_status(302)
      end

      it 'should create the requirement (not admin)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        post :remove_trainings
        expect(flash[:alert]).to eq("You cannot access this area.")
        expect(response).to redirect_to root_path
      end

    end

  end

end




