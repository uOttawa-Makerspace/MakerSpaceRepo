require 'rails_helper'

RSpec.describe ExamsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    5.times { create(:exam, user: @admin) }
    @exam = create(:exam)
  end

  before(:each) do
    session[:user_id] = @admin.id
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@exams).count).to eq(5)
      end
    end

    context 'logged as regular user' do
      it 'should return 200 response' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(@controller.instance_variable_get(:@exams).count).to eq(0)
      end
    end
  end

  describe 'private' do
    context '/create_exam_and_exam_questions' do
      it 'should create exam and exam questions' do
        training = create(:training_with_questions)
        training_session = create(:training_session_with_users, training: training)
        user = create(:user, :regular_user)
        training_session.users << user
        expect{ @controller.send(:create_exam_and_exam_questions, user, training_session) }.to change{ Exam.count }.by(1)
                                                                                                   .and change{ ExamQuestion.count }.by($n_exams_question)
        expect(Exam.last.category).to eq(training_session.training.name)
        expect(flash[:notice]).to eq("You've successfully sent exams to all users in this training.")
      end
    end
  end

  describe "GET /show" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :show, params: {id: @exam.id}
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as exam's user /grant_access" do
      it 'should return 200 response' do
        user = @exam.user
        session[:user_id] = user.id
        get :show, params: {id: @exam.id}
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as another regular user /grant_access' do
      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :show, params: {id: @exam.id}
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end

    context 'if exam is completed, the user cannot access the exam anymore /check_exam_status' do
      it 'should redirect user to exams path because exam is done' do
        exam = create(:exam, status: Exam::STATUS[:passed])
        user = exam.user
        session[:user_id] = user.id
        get :show, params: {id: exam.id}
        expect(response).to redirect_to exams_path
        expect(flash[:alert]).to eq('You cannot access an exam after being finished.')
      end

      it 'should redirect user to exams path because exam is done' do
        exam = create(:exam, status: Exam::STATUS[:failed])
        user = exam.user
        session[:user_id] = user.id
        get :show, params: {id: exam.id}
        expect(response).to redirect_to exams_path
        expect(flash[:alert]).to eq('You cannot access an exam after being finished.')
      end
    end
  end

  # describe 'POST /create' do
  #   context 'logged as admin' do
  #     it 'should create an exam and redirect' do
  #       training = create(:training)
  #       expect { post :create, params: { exam: { training_id: training.id } } }.to change(Exam, :count).by(1)
  #                                                                                  .and change(ExamQuestion, :count).by($n_exams_question)
  #       expect(flash[:notice]).to eq("You've successfully created a new exam!")
  #       expect(response).to redirect_to exams_path
  #     end
  #   end
  # end

  describe 'GET /create_from_training' do
    context 'logged as admin' do
      it 'should create an exam and redirect' do
        training = create(:training_with_questions)
        training_session = create(:training_session_with_users, training: training)
        n_users = training_session.users.count
        expect { get :create_from_training, params: { training_session_id: training_session.id } }.to change(Exam, :count).by(n_users)
                                                                                            .and change(ExamQuestion, :count).by(n_users*$n_exams_question)
        expect(ActionMailer::Base.deliveries.count).to eq(n_users)
        expect(flash[:notice]).to eq("You've successfully sent exams to all users in this training.")
        expect(response).to redirect_to staff_dashboard_index_path(space_id: training_session.space.id)
      end
    end
  end

  describe 'GET /create_for_single_user' do
    context 'logged as admin' do
      it 'should create an exam and redirect' do
        training = create(:training_with_questions)
        training_session = create(:training_session_with_users, training: training)
        user = create(:user, :regular_user)
        expect { get :create_for_single_user, params: { user_id: user.id, training_session_id: training_session.id } }.to change(Exam, :count).by(1)
                                                                                                          .and change(ExamQuestion, :count).by($n_exams_question)
        expect(flash[:notice]).to eq("You've successfully sent exams to all users in this training.")
        expect(response).to redirect_to staff_training_session_path(training_session.id)
      end
    end
  end

  describe 'GET /finish_exam' do
    context 'logged as admin' do
      it 'should updated exam, create certification, send email and redirect to exams path' do
        exam = create(:exam_with_exam_questions_and_exam_responses)
        expect { get :finish_exam, params: { exam_id: exam.id } }.to change(Certification, :count).by(1)
        updated_exam = Exam.find(exam.id)
        expect(updated_exam.status).to eq(Exam::STATUS[:passed])
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(flash[:notice]).to eq("Score: 100. You passed the exam.")
        expect(response).to redirect_to exams_path
      end

      it 'should updated exam, create a new exam, not create a certification, send email and redirect to exams path' do
        training = create(:training_with_questions)
        training_session = create(:training_session_with_users, training: training)
        exam = create(:exam_with_exam_questions_and_exam_responses_wrong, training_session: training_session)
        expect { get :finish_exam, params: { exam_id: exam.id } }.to change(Certification, :count).by(0)
                                                                .and change(Exam, :count).by(1)
                                                                .and change(ExamQuestion, :count).by($n_exams_question)
        updated_exam = Exam.find(exam.id)
        expect(updated_exam.status).to eq(Exam::STATUS[:failed])
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(flash[:notice]).to eq("Score: 0. You failed the exam.")
        expect(response).to redirect_to exams_path
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the question' do
        expect { delete :destroy, params: {id: @exam.id} }.to change(Exam, :count).by(-1)
        expect(response).to redirect_to exams_path
        expect(flash[:notice]).to eq('Exam Deleted')
      end
    end
  end
end

