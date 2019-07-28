class ExamsController < ApplicationController
  before_action :current_user
  before_action :grant_access

  def index
    @exams = Exam.all.order(category: :desc).paginate(:page => params[:page], :per_page => 50)
  end

  def new
    @new_exam = Exam.new
    @categories = Question::CATEGORIES
  end

  def create
    @new_exam = current_user.exams.new(exam_params)
    @new_exam.save!
    ExamQuestion.create_exam_questions(@new_exam.id, @new_exam.category, 3)
    if @new_exam.save!
      redirect_to exams_path
      flash[:notice] = "You've successfully created a new exam!"
    end
  end

  def show
    @exam = Exam.find(params[:id])
  end

  def destroy
    exam = Exam.find(params[:id])
    if exam.destroy
      flash[:notice] = "Exam Deleted"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to exams_path
  end

  private

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end

  def exam_params
    params.require(:exam).permit(:category)
  end
end
