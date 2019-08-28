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
    @categories = Training.all.pluck(:name, :id)
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
      MsrMailer.send_exam(user, training_session).deliver_now
    end
    redirect_to staff_dashboard_index_path(space_id: training_session.space.id)
  end

  def create_for_single_user
    training_session = TrainingSession.find(params[:training_session_id])
    user = User.find(params[:user_id])
    create_exam_and_exam_questions(user, training_session)
    redirect_to staff_training_session_path(training_session.id)
    # SEND EMAIL
  end

  def show
    # TODO: User cannot open new tab when clicking "Finish Exam"
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
    user = exam.user
    score = exam.calculate_score
    training_session = exam.training_session
    if score < Exam::SCORE_TO_PASS
      status = Exam::STATUS[:failed]
      create_exam_and_exam_questions(user, training_session) if user.exams.where(training_session_id: training_session.id).count < 2
      # TODO: Prevent user to go back to exam after finished
    else
      status = Exam::STATUS[:passed]
      Certification.certify_user(training_session.id, user.id)
    end
    exam.update_attributes(status: status, score: score)
    MsrMailer.finishing_exam(user, exam).deliver_now
    MsrMailer.exam_results_staff(user, exam).deliver_now
    flash[:notice] = "Score: #{score}. You #{status} the exam."
    redirect_to exams_path
  end

  private

  def create_exam_and_exam_questions(user, training_session)
    new_exam = user.exams.new(:training_session_id => training_session.id,
                              :category => training_session.training.name, :expired_at => DateTime.now + 3.days)
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
