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
    training_session = TrainingSession.find(params[:training_session_id])
    training_session.users.find_each do |user|
      create_exam_and_exam_questions(user, training_session)
    end
    redirect_to staff_training_session_path(training_session.id)
  end

  def create_for_single_user
    training_session = TrainingSession.find(params[:training_session_id])
    user = User.find(params[:user_id])
    create_exam_and_exam_questions(user, training_session)
    redirect_to staff_training_session_path(training_session.id)
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

  def create_exam_and_exam_questions(user, training_session)
    new_exam = user.exams.new(:training_session_id => training_session.id,
                              :category => training_session.training.name)
    new_exam.save!
    if ExamQuestion.create_exam_questions(new_exam.id, new_exam.category, $n_exams_question)
      flash[:notice] = "You've successfully sent exams to all users in this training."
    else
      flash[:alert] = "Something went wrong"
    end
  end

  def set_exam
    @exam = Exam.find_by(id: params[:id]) || Exam.new
  end

  def grant_access
    unless @exam.user.eql?(current_user) || current_user.staff?
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
