
require 'rails_helper'

RSpec.describe LearningModuleTrackController, type: :controller do

  describe "#index" do

    context "index" do

      it 'should show the index page' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#start" do

    context "start" do

      it 'should create a learning module track' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        lm = create(:learning_module)
        get :start, params: {learning_module_id: lm.id}
        expect(LearningModuleTrack.last.user_id).to eq(user.id)
        expect(LearningModuleTrack.last.learning_module_id).to eq(lm.id)
        expect(LearningModuleTrack.last.status).to eq("In progress")
        expect(response).to redirect_to learning_area_path(lm.id)
      end

    end

  end

  describe "#completed" do

    context "completed" do

      it 'should update a learning module track' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        lm = create(:learning_module)
        get :start, params: {learning_module_id: lm.id}
        get :completed, params: {learning_module_id: lm.id}
        expect(LearningModuleTrack.last.status).to eq("Completed")
        expect(response).to redirect_to learning_area_path(lm.id)
      end

    end

  end

end




