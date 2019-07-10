class QuestionsController < ApplicationController
  layout 'staff_area'
  before_action :current_user
  before_action :grant_access

  def index
    @questions = Question.all.order(created_at: :desc).paginate(:page => params[:page], :per_page => 50)
  end

  def new
    @new_question = Question.new
    @categories = Question::CATEGORIES
    5.times{@new_question.answers.new}
  end

  def create
    @new_question = current_user.questions.new(question_params)
    @new_question.answers.first.correct = true
    if @new_question.save!
      redirect_to questions_path
      flash[:notice] = "You've successfully created a new question!"
    end
  end

  def show
    @question = Question.find(params[:id])
  end

  def edit
    @question = Question.find(params[:id])
    @categories = Question::CATEGORIES
  end

  def update
    question = Question.find(params[:id])
    if question.update(question_params)
      flash[:notice] = "Question updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to questions_path
  end

  def destroy
    question = Question.find(params[:id])
    if question.destroy
      flash[:notice] = "Question Deleted"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to questions_path
  end

  private

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end

  def question_params
    params.require(:question).permit(:description, :category, answers_attributes:[:id, :description, :correct])
  end
end
