class Staff::TrainingSessionsController < StaffAreaController
  before_action :load_user, only: [:show, :edit, :update]

  layout 'staff_area'

  def index
    if sort_params
      if params[:p] == "signed_in_users"
        if !params[:sort].present? && !params[:direction].present?
          params[:sort] = "lab_sessions.sign_in_time"
          params[:direction] = "desc"
        end
        @users_temp = LabSession.joins(:user).where("sign_out_time > ?", Time.now)
        if params[:location].present?
          @users_temp = @users_temp.joins("INNER JOIN pi_readers ON pi_mac_address = mac_address AND LOWER(pi_location) = LOWER('#{params[:location]}')")
        end
        @users_temp = @users_temp.order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        @users = @users_temp.includes(:user).map{|session| session.user}
        @total_pages = @users_temp.total_pages
      elsif params[:p] == "new_users" || !params[:p].present?
        if !params[:sort].present? && !params[:direction].present?
          params[:sort] = "users.created_at"
          params[:direction] = "desc"
        end
        @users = User.includes(:lab_sessions).order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        @total_pages = @users.total_pages
      end
    else
      redirect_to staff_index_path
      flash[:alert] = "Invalid parameters!"
    end
  end

  def sort_params
    if (((["username","name","lab_sessions.sign_in_time","users.created_at"].include? params[:sort]) && (["desc","asc"].include? params[:direction])) || (!params[:sort].present? && !params[:direction].present?))
      return true
    end
  end

  def new
    training_session = TrainingSession.new(training_session_params)
    if params['training_session_users'].present?
      params['training_session_users'].each do |user|
        training_session.users << User.find(user)
      end
    end
    redirect_to :back
  end

  def create
    staff = current_user
    training_session = TrainingSession.new(training_session_params)
    if training_session.save
      flash[:notice] = "Training session created succesfully"
    end
    redirect_to staff_training_sessions_url
  end

  def change_training_type
    staff = current_user
    training_session = TrainingSession.find_by(training_session_params)
    if params['training_session_new_training_id'].present?
      training_session.training_id = params['training_session_new_training_id']
      if training_session.save
        flash[:notice] = "Training session renamed succesfully"
      end
    end
    redirect_to :back
  end

  def reschedule_training_session
    staff = current_user
    training_session = TrainingSession.find_by(training_session_params)
    if params['training_session_new_time'].present?
      training_session.timeslot = params['training_session_new_time']
      if training_session.save
        flash[:notice] = "Training session rescheduled succesfully"
      end
    end
    redirect_to :back
  end

  def delete_training_session
    staff = current_user
    training_session = TrainingSession.find_by(training_session_params)
    if training_session.destroy
        flash[:notice] = "Training session deleted succesfully"
    end
    redirect_to :back
  end

  def add_trainees_to_training_session
    staff = current_user
    training_session = TrainingSession.find_by(training_session_params)
    params['training_session_new_trainees'].each do |trainee|
      unless training_session.users.include? User.find(trainee)
        training_session.users << User.find(trainee)
      end
    end
    if training_session.save
      flash[:notice] = "Users successfuly added to the training session"
    end
    redirect_to :back
  end

  def certify_trainees
    staff = current_user
    training_session = TrainingSession.find_by(training_session_params)
    if params['training_session_graduates'].present?
      params['training_session_graduates'].each do |graduate|
         if training_session.users.include? User.find(graduate)
           unless User.find(graduate).certifications.include? Certification.find_by(training: Training.find(training_session_params['training_id']).name)
             certification = Certification.new(user_id: graduate, trainer_id: staff.id, training: Training.find(training_session_params['training_id']).name)
             certification.save
           end
         end
       end
       flash[:notice] = "Users certified successfuly"
     end
     redirect_to :back
  end


  private

    def training_session_params
      params.require(:training_session).permit(:user_id, :training_id, :timeslot, :course)
    end

end
