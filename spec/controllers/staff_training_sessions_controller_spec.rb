require 'rails_helper'

RSpec.describe Staff::TrainingSessionsController, type: :controller do
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

  describe 'GET /new' do
    context 'logged as admin' do
      it 'should return a 200' do
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /create' do
    context 'logged as admin' do
      it 'should create a training session and redirect' do
        training = create(:training_with_spaces)
        users = 3.times.inject([]) { |arr| arr << create(:user, :regular_user) }
        training_session_params = { user_id: @admin.id, training_id: training.id, course: 'no course', training_session: {space_id: training.spaces.first.id}, level: "Beginner", training_session_users: users.pluck(:id) }
        expect { post :create, params: training_session_params }.to change(TrainingSession, :count).by(1)
        expect(TrainingSession.last.users.count).to eq(users.count)
        expect(response).to redirect_to staff_training_session_path(TrainingSession.last.id)
      end
    end
  end

  describe 'PATCH /update' do
    context 'logged as admin' do
      context 'logged as staff user' do
        it 'should not update training session, verify if user owns the training session and redirect user to root' do
          staff = create(:user, :staff)
          session[:user_id] = staff.id
          patch :update, params: { id: @training_session.id, changed_params: {training_id: @training_session.id, user_id: staff.id } }
          expect(flash[:alert]).to eq("Can't access training session")
          expect(response).to redirect_to new_staff_training_session_path
        end

        it 'should not update training session, verify if user owns the training session and redirect user to root' do
          training_session = create(:training_session, :staff_user)
          staff = training_session.user
          session[:user_id] = staff.id
          patch :update, params: { id: training_session.id, changed_params: {training_id: @training_session.id, user_id: staff.id } }
          expect(flash[:alert]).to eq("You're not an admin.")
          expect(response).to redirect_to root_path
        end
      end

      context 'logged as admin user' do
        it 'should update the training session' do
          admin = create(:user, :admin)
          patch :update, params: {id: @training_session.id, changed_params: {training_id: @training_session.id, user_id: admin.id } }
          expect(TrainingSession.find(@training_session.id).user.id).to eq(admin.id)
          expect(flash[:notice]).to eq('Training session updated succesfully')
          expect(response).to redirect_to root_path
        end
      end
    end
  end

  describe 'POST /certify_trainees' do
    context 'logged as admin' do
      it 'should create certifications for all users in training session' do
        training_session = create(:training_session_with_users)
        expect(training_session.users.count).to eq(5)
        post :certify_trainees, params: { id: training_session }
        training_session.users.each do |user|
          expect(Certification.find_by(user_id: user.id, training_session_id: training_session.id).present?).to eq(true)
        end
        expect(response).to redirect_to staff_index_path
        expect(flash[:notice]).to eq('Training Session Completed Successfully')
      end
    end
  end

  describe 'PATCH /renew_certification' do
    context 'logged as admin' do
      it 'should renew certification' do
        certification = create(:certification, created_at: DateTime.yesterday.in_time_zone , updated_at: DateTime.yesterday.in_time_zone )
        patch :renew_certification, params: { id: certification.training_session.id, cert_id: certification.id }
        expect(Certification.find(certification.id).updated_at.strftime("%Y%m%d%H%M")).to eq(DateTime.now.in_time_zone.strftime("%Y%m%d%H%M"))
        expect(response).to redirect_to user_path(certification.user.username)
        expect(flash[:notice]).to eq('Renewed Successfully')
      end
    end
  end

  describe 'DELETE /revoke_certification' do
    context 'logged as admin' do
      it 'should delete certification' do
        certification = create(:certification)
        expect{ patch :revoke_certification, params: { id: certification.training_session.id, cert_id: certification.id } }.to change(Certification, :count).by(-1)
        expect(Certification.find_by(id: certification.id)).to eq(nil)
        expect(response).to redirect_to user_path(certification.user.username)
        expect(flash[:notice]).to eq('Deleted Successfully')
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the training session' do
        expect { delete :destroy, params: {id: @training_session.id} }.to change(TrainingSession, :count).by(-1)
        expect(flash[:notice]).to eq('Deleted Successfully')
        expect(response).to redirect_to staff_index_path
      end
    end
  end

  describe "GET /training_report" do
    context 'logged as admin' do
      it 'should destroy the training session' do
        get :training_report, params: {:id => @training_session.id}, format: :xlsx
        expect(response).to have_http_status(:success)
      end
    end
  end
end

