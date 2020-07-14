require 'rails_helper'

RSpec.describe QuestionsController, type: :controller do
  before(:all) do
    7.times { create(:question_with_answers) }
    @admin = create(:user, :admin)
    @question = Question.last
  end

  before(:each) do
    session[:user_id] = @admin.id
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@questions).count).to eq(7)
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  describe 'GET /new' do
    context 'logged as admin' do
      it 'should return a 200' do
        session[:user_id] = @admin.id
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /show" do
    context 'logged as admin' do
      it 'should return 200 response' do
        session[:user_id] = @admin.id
        get :show, params: {id: @question.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /edit" do
    context 'logged as admin' do
      it 'should return 200 response' do
        session[:user_id] = @admin.id
        get :edit, params: {id: @question.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /create' do
    context 'logged as admin' do
      it 'should create a question with answers and redirect' do
        session[:user_id] = @admin.id
        answer_params = (0..5).inject([]) { |arr, l| arr << FactoryBot.attributes_for(:answer) }
        question_params = FactoryBot.attributes_for(:question, :answers_attributes => answer_params)
        expect { post :create, params: {question: question_params} }.to change(Question, :count).by(1)
        expect(flash[:notice]).to eq("You've successfully created a new question!")
        expect(response).to redirect_to questions_path
      end
    end
  end
  #
  # describe 'PATCH /update' do
  #   context 'logged as admin' do
  #     it 'should update the announcement' do
  #       session[:user_id] = @admin.id
  #       patch :update, params: {id: @announcement_all.id, announcement: {public_goal: "volunteer"} }
  #       expect(response).to redirect_to announcements_path
  #       expect(Announcement.find(@announcement_all.id).public_goal).to eq("volunteer")
  #       expect(flash[:notice]).to eq("Announcement updated")
  #     end
  #   end
  # end
  #
  # describe "DELETE /destroy" do
  #   context 'logged as admin' do
  #     it 'should destroy the announcement' do
  #       session[:user_id] = @admin.id
  #       expect {  delete :destroy, params: {id: @announcement_all.id} }.to change(Announcement, :count).by(-1)
  #       expect(response).to redirect_to announcements_path
  #       expect(flash[:notice]).to eq("Announcement Deleted")
  #     end
  #   end
  # end

  after(:all) do
    Question.destroy_all
  end
end

