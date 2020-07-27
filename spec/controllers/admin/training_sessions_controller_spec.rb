require 'rails_helper'

RSpec.describe Admin::TrainingSessionsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @training_session = create(:training_session)
  end

  before(:each) do
    session[:user_id] = @admin.id
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
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

  describe 'PATCH /update' do
    context 'logged as admin' do
      it 'should not update the training session because user is nor staff' do
        user = create(:user, :regular_user)
        patch :update, params: {id: @training_session.id, training_session: {user_id: user.id} }
        expect(TrainingSession.find(@training_session.id).user.id).not_to eq(user.id)
        expect(flash[:alert]).to eq('Something went wrong')
        expect(response).to redirect_to root_path
      end

      it 'should update the training session' do
        user = create(:user, :admin)
        patch :update, params: {id: @training_session.id, training_session: {user_id: user.id} }
        expect(TrainingSession.find(@training_session.id).user.id).to eq(user.id)
        expect(flash[:notice]).to eq('Updated Successfully')
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the training session' do
        expect { delete :destroy, params: {id: @training_session.id} }.to change(TrainingSession, :count).by(-1)
        expect(flash[:notice]).to eq('Deleted Successfully')
        expect(response).to redirect_to root_path
      end
    end
  end
end

