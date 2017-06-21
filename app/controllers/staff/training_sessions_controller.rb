class Staff::TrainingSessionsController < StaffAreaController
  before_action :current_training_session, only: [:show, :edit, :update, :certify_trainees, :delete_training_session]

  layout 'staff_area'

  def index

  end

  def new
    @new_training_session = TrainingSession.new
  end

  def create
    @training_session = TrainingSession.new(training_session_params)
    if params['training_session_users'].present?
      params['training_session_users'].each do |user|
        @training_session.users << User.find(user)
      end
    end
    if @training_session.save
      flash[:notice] = "Training session created succesfully"
      render json: { redirect_uri: "#{staff_training_session_path(@training_session.id)}" }
    else
      flash[:alert] = "Something went wrong. Please try again."
      redirect_to :back
    end
  end

  def update
    # new training type
    if params['training_session_new_training_id'].present?
      @current_training_session.training_id = params['training_session_new_training_id']
    end
    # add trainee(s)
    if params['training_session_new_trainees'].present?
      params['training_session_new_trainees'].each do |trainee|
        unless @current_training_session.users.include? User.find(trainee)
          @current_training_session.users << User.find(trainee)
        end
      end
    end
    # change time
    if params['training_session_new_time'].present?
      @current_training_session.timeslot = params['training_session_new_time']
    end
    # save
    if @current_training_session.save
      flash[:notice] = "Training session updated succesfully"
    end
    redirect_to :back
  end

  def certify_trainees
    staff = current_user
    if params['training_session_graduates'].present?
      params['training_session_graduates'].each do |graduate|
         if @current_training_session.users.include? User.find(graduate)
           unless User.find(graduate).certifications.include? Certification.find_by(training: @current_training_session.training.name)
             certification = Certification.new(user_id: graduate, trainer_id: staff.id, training: @current_training_session.training.name)
             certification.save
           end
         end
       end
       flash[:notice] = "Users certified successfuly"
     end
     redirect_to :back
  end

  def delete_training_session
    if @current_training_session.destroy
        flash[:notice] = "Training session deleted succesfully"
    end
    redirect_to :back
  end

  private

    def training_session_params
      params.require(:training_session).permit(:user_id, :training_id, :timeslot, :course)
    end

    def current_training_session
      @current_training_session = TrainingSession.find(params[:id])
    end

end
