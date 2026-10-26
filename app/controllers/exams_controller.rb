class ExamsController < SessionsController
  before_action :current_user
  before_action :set_exam
  before_action :signed_in,
                only: %i[create_from_training create_for_single_user destroy finish_exam]
  before_action :grant_access, only: [:show]
  before_action :check_exam_status, only: [:show]
  before_action :only_admin_access, only: [:destroy]
  before_action :only_session_staff_access,
                only: %i[create_from_training create_for_single_user]
  before_action :only_owner_access, :only_open_exam, only: [:finish_exam]

  def index
    @pagy, @exams = pagy(current_user.exams.order(category: :desc), limit: 50)
  end

  def create_from_training
    training_session = @training_session
    training_session.users.find_each do |user|
      create_exam_and_exam_questions(user, training_session)
      MsrMailer.send_exam(user, training_session).deliver_now
    end
    redirect_to staff_dashboard_index_path(space_id: training_session.space.id)
  end

  def create_for_single_user
    training_session = @training_session
    user = User.find(params[:user_id])
    create_exam_and_exam_questions(user, training_session)
    redirect_to staff_training_session_path(training_session.id)
    # SEND EMAIL
  end

  def show
    # TODO: User cannot open new tab when clicking "Finish Exam"
    @exam = Exam.find(params[:id])
    if @exam.status == Exam::STATUS[:not_started] && @exam.user.eql?(current_user)
      @exam.update(status: Exam::STATUS[:incomplete])
    end
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
    exam = @exam
    user = exam.user
    score = exam.calculate_score
    training_session = exam.training_session
    if score < Exam::SCORE_TO_PASS
      status = Exam::STATUS[:failed]
      if user.exams.where(training_session_id: training_session.id).count < 2
        create_exam_and_exam_questions(user, training_session)
      end
    else
      status = Exam::STATUS[:passed]
      Certification.certify_user(training_session.id, user.id, training_session.level)
    end
    exam.update(status: status, score: score)
    MsrMailer.finishing_exam(user, exam).deliver_now
    # MsrMailer.exam_results_staff(user, exam).deliver_now
    flash[:notice] = "Score: #{score}. You #{status} the exam."
    redirect_to exams_path
  end

  private

  def create_exam_and_exam_questions(user, training_session)
    new_exam =
      user.exams.new(
        training_session_id: training_session.id,
        category: training_session.training.name_en,
        expired_at: DateTime.now + 3.days
      )
    new_exam.save!
    if ExamQuestion.create_exam_questions(
         new_exam.id,
         new_exam.training.id,
         $n_exams_question,
         training_session.level
       )
      flash[
        :notice
      ] = "You've successfully sent exams to all users in this training."
    else
      flash[:alert] = "Something went wrong"
    end
  end

  def set_exam
    @exam = Exam.find_by(id: params[:id]) || Exam.new
  end

  def only_admin_access
    return if current_user.admin?
    flash[:alert] = "You cannot access this area."
    redirect_to root_path
  end

  def only_session_staff_access
    @training_session = TrainingSession.find(params[:training_session_id])
    return if current_user.admin? || @training_session.user.eql?(current_user)
    flash[:alert] = "You cannot access this area."
    redirect_to root_path
  end

  def only_owner_access
    @exam = Exam.find(params[:exam_id])
    return if @exam.user.eql?(current_user)
    flash[:alert] = "You cannot access this area."
    redirect_to root_path
  end

  def only_open_exam
    return if @exam.open_for_answers?
    flash[:alert] =
      if @exam.ungraded?
        "This exam has expired."
      else
        "You cannot finish an exam that is already finished."
      end
    redirect_to exams_path
  end

  def grant_access
    return if @exam.user.eql?(current_user) || current_user.staff?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    
  end

  def check_exam_status
    if !@exam.open_for_answers?
      flash[:alert] =
        if @exam.ungraded?
          "This exam has expired."
        else
          "You cannot access an exam after being finished."
        end
      redirect_to exams_path
    end
  end
end
