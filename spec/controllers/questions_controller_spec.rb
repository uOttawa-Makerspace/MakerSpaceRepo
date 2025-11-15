require "rails_helper"

RSpec.describe QuestionsController, type: :controller do
  let(:space) { create(:space) }
  let(:admin) { create(:user, :admin, space: space) }  # Associate space with admin
  let(:question) { create(:question_with_answers) }

  before(:each) do
    session[:user_id] = admin.id
  end

  describe "GET /index" do
    context "logged as admin" do
      it "should return 200 response" do
        space # Ensure space is created
        7.times { create(:question_with_answers) }
        
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@questions).count).to eq(0)
        expect(Question.all.count).to eq(7)
      end
    end

    context "logged as regular user" do
      it "should redirect user to root" do
        space # Ensure space exists
        user = create(:user, :regular_user, space: space)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "GET /new" do
    context "logged as admin" do
      it "should return a 200" do
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /show" do
    context "logged as admin" do
      it "should return 200 response" do
        get :show, params: { id: question.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /edit" do
    context "logged as admin" do
      it "should return 200 response" do
        get :edit, params: { id: question.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /create" do
    context "logged as admin" do
      it "should create a question with answers and redirect" do
        answer_params = (0..5).map { FactoryBot.attributes_for(:answer) }
        question_params = FactoryBot.attributes_for(
          :question,
          answers_attributes: answer_params
        )
        
        expect {
          post :create, params: { question: question_params }
        }.to change(Question, :count).by(1)
        
        expect(flash[:notice]).to eq("You've successfully created a new question!")
        expect(response).to redirect_to questions_path
      end
    end
  end

  describe "PATCH /update" do
    context "logged as admin" do
      it "should update the question" do
        patch :update,
              params: {
                id: question.id,
                question: { description: "updated" }
              }
        
        expect(response).to redirect_to questions_path
        expect(Question.find(question.id).description).to eq("updated")
        expect(flash[:notice]).to eq("Question updated")
      end
    end
  end

  describe "DELETE /destroy" do
    context "logged as admin" do
      it "should destroy the question" do
        question # Create it first
        
        expect { 
          delete :destroy, params: { id: question.id } 
        }.to change(Question, :count).by(-1)
        
        expect(response).to redirect_to questions_path
        expect(flash[:notice]).to eq("Question Deleted")
      end
    end
  end
end