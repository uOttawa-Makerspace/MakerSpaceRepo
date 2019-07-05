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
    @volunteer_task = VolunteerTask.find(params[:id])
    @new_volunteer_join = VolunteerTaskJoin.new
    @new_required_training = RequireTraining.new
    trainings_already_added = @volunteer_task.require_trainings.pluck(:training_id)
    @trainings = Training.where.not(id: trainings_already_added).pluck(:name, :id)
    @user_trainings = user_trainings
    @volunteer_task_trainings = volunteer_task_trainings
    if current_user.staff?
      @volunteers = User.where(:role => "volunteer").where.not(:id => @volunteer_task.volunteer_task_joins.pluck(:user_id)).pluck(:name, :id)
      @staff = User.where("users.role = ? OR users.role = ?", "staff", "admin").where.not(:id => @volunteer_task.volunteer_task_joins.pluck(:user_id)).pluck(:name, :id)
      @volunteers_in_task = User.where(:role => "volunteer").where(:id => @volunteer_task.volunteer_task_joins.pluck(:user_id)).pluck(:name, :id)
      @staff_in_task = User.where("users.role = ? OR users.role = ?", "staff", "admin").where(:id => @volunteer_task.volunteer_task_joins.pluck(:user_id)).pluck(:name, :id)
    end
  end

  def edit
    @volunteer_task = VolunteerTask.find(params[:id])
  end

  def update
    volunteer_task = VolunteerTask.find(params[:id])
    if volunteer_task.update(volunteer_task_params)
      flash[:notice] = "Volunteer task updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to volunteer_tasks_path
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
