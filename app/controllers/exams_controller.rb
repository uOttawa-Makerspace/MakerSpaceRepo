class ExamsController < ApplicationController
  before_action :current_user
  before_action :set_exam
  before_action :grant_access, only: [:show]
  before_action :check_exam_status, only: [:show]

  def index
    @exams = current_user.exams.order(category: :desc).paginate(:page => params[:page], :per_page => 50)
  end

  def new
    @new_exam = Exam.new
    @categories = Question::CATEGORIES
  end

  def create
    @new_exam = current_user.exams.new(exam_params)
    @new_exam.save!
    ExamQuestion.create_exam_questions(@new_exam.id, @new_exam.category, $n_exams_question)
    if @new_exam.save!
      redirect_to exams_path
      flash[:notice] = "You've successfully created a new exam!"
    end
  end

  def create_from_training
    @current_training_session.users.find_each do |user|
      new_exam = user.exams.new(:training_session_id => @current_training_session.id,
                                :category => @current_training_session.training.name)
      new_exam.save!
      if new_exam.create_exam_questions(new_exam.id, new_exam.category, $n_exams_question)
        redirect_to :back
        flash[:notice] = "You've successfully sent exams to all users in this training."
      end
    end
  end

  def show
    @exam = Exam.find(params[:id])
    @exam.update_attributes(:status => Exam::STATUS[:incomplete]) if @exam.status == Exam::STATUS[:not_started]
    @questions = @exam.questions
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

  def finish_exam
    exam = Exam.find(params[:exam_id])
    score = exam.calculate_score
    if score < Exam::SCORE_TO_PASS
      status = Exam::STATUS[:failed]
    else
      status = Exam::STATUS[:passed]
    end
    exam.update_attributes(status: status, score: score)
    flash[:notice] = "Score: #{score}. You #{status} the exam."
    redirect_to exams_path
  end

  private

  def set_exam
    @exam = Exam.find_by(id: params[:id]) || Exam.new
  end

  def grant_access
    unless @exam.user.eql?(current_user)
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end

  def exam_params
    params.require(:exam).permit(:category)
  end

  def check_exam_status
    unless (@exam.status == Exam::STATUS[:incomplete] || @exam.status == Exam::STATUS[:not_started])
      flash[:alert] = "You cannot access an exam after being finished."
      redirect_to exams_path
    end
  end
end
