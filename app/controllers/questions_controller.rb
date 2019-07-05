class QuestionsController < ApplicationController
  before_action :current_user
  before_action :grant_access

  def index
    @questions = Question.all.order(created_at: :desc).paginate(:page => params[:page], :per_page => 50)
  end

  def new
    @new_question = Question.new
  end

  def create
    @question = Question.new(question_params)
    @question.user_id = @user.id
    if @question.save!
      redirect_to questions_path
      flash[:notice] = "You've successfully created a new question!"
    end
  end

  def show
    @question = Question.find(params[:id])
  end

  def edit
    @question = Question.find(params[:id])
  end

  def update
    question = Question.find(params[:id])
    if question.update(volunteer_task_params)
      flash[:notice] = "Question updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to questions_path
  end

  def destroy
    volunteer_task = VolunteerTask.find(params[:id])
    if volunteer_task.destroy
      flash[:notice] = "Volunteer Task Deleted"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to volunteer_tasks_path
  end

  private

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end

  def question_params
    params.require(:question).permit(:description, :category)
  end
end
