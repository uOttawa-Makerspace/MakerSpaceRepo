require 'rails_helper'

RSpec.describe ExamResponsesController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @user = create(:user, :regular_user)
    @exam = create(:exam_with_exam_questions, user: @user)
    @question = @exam.questions.first
  end

  before(:each) do
    session[:user_id] = @user.id
  end

  describe "#grant_access" do
    context 'logged as another regular user' do
      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        post :create, params: {exam_id: @exam.id}
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('Do not try this')
      end
    end
  end

  describe 'POST /create' do
    context 'logged user associated with exam' do
      it 'should create a exam response' do
        answer = @question.answers.first
        expect { post :create, params: {exam_id: @exam.id, answer_id: answer.id}, format: :js }.to change(ExamResponse, :count).by(1)
      end

      it 'should update exam response since it was already created' do
        first_answer = @question.answers.first
        last_answer = @question.answers.last
        expect { post :create, params: {exam_id: @exam.id, answer_id: first_answer.id}, format: :js }.to change(ExamResponse, :count).by(1)
        expect { post :create, params: {exam_id: @exam.id, answer_id: last_answer.id}, format: :js }.to change(ExamResponse, :count).by(0)
        exam_response = @question.response_for_exam(@exam)
        expect(exam_response.answer).to eq(last_answer)
      end
    end
  end

  after(:all) do
    Question.destroy_all
  end
end

