require 'rails_helper'

RSpec.describe ExamsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    5.times { create(:exam, user: @admin) }
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

  #
  # describe "GET /show" do
  #   context 'logged as admin' do
  #     it 'should return 200 response' do
  #       get :show, params: {id: @question.id}
  #       expect(response).to have_http_status(:success)
  #     end
  #   end
  # end
  #
  # describe "GET /edit" do
  #   context 'logged as admin' do
  #     it 'should return 200 response' do
  #       get :edit, params: {id: @question.id}
  #       expect(response).to have_http_status(:success)
  #     end
  #   end
  # end
  #
  # describe 'POST /create' do
  #   context 'logged as admin' do
  #     it 'should create a question with answers and redirect' do
  #       answer_params = (0..5).inject([]) { |arr, l| arr << FactoryBot.attributes_for(:answer) }
  #       question_params = FactoryBot.attributes_for(:question, :answers_attributes => answer_params)
  #       expect { post :create, params: {question: question_params} }.to change(Question, :count).by(1)
  #       expect(flash[:notice]).to eq("You've successfully created a new question!")
  #       expect(response).to redirect_to questions_path
  #     end
  #   end
  # end
  #
  # describe 'PATCH /update' do
  #   context 'logged as admin' do
  #     it 'should update the question' do
  #       patch :update, params: {id: @question.id, question: {description: "updated"} }
  #       expect(response).to redirect_to questions_path
  #       expect(Question.find(@question.id).description).to eq("updated")
  #       expect(flash[:notice]).to eq("Question updated")
  #     end
  #   end
  # end
  #
  # describe "DELETE /destroy" do
  #   context 'logged as admin' do
  #     it 'should destroy the question' do
  #       expect {  delete :destroy, params: {id: @question.id} }.to change(Question, :count).by(-1)
  #       expect(response).to redirect_to questions_path
  #       expect(flash[:notice]).to eq("Question Deleted")
  #     end
  #   end
  # end
  #
  # after(:all) do
  #   Question.destroy_all
  # end
end

