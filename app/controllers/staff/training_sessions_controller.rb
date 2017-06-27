class Staff::TrainingSessionsController < StaffAreaController
  before_action :current_training_session, only: [:show, :edit, :update, :certify_trainees, :delete_training_session]
  before_action :changed_params, only: [:update]

  layout 'staff_area'

  def index

  end

  def new
    @new_training_session = TrainingSession.new
  end

  def create
    @training_session = TrainingSession.new(training_session_params)
    if params['training_session_users'].present?
      JSON.parse(params['training_session_users']).each do |user|
        @training_session.users << User.find_by(username: user)
      end
    end
    if @training_session.save
      redirect_to "#{staff_training_session_path(@training_session.id)}"
    else
      redirect_to :back
      flash[:alert] = "Something went wrong. Please try again."
    end
  end

  def update
    #binding.pry
    @current_training_session.update(changed_params)
    if params['users'].present?
      JSON.parse(params['users']).each do |new_user|
        unless @current_training_session.users.include? User.find_by(username: new_user)
          @current_training_session.users << User.find_by(username: new_user)
        end
      end
      @current_training_session.users.each do |old_user|
        unless JSON.parse(params['users']).include? old_user.username
          @current_training_session.users.delete(old_user)
        end
      end
    end

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
             unless certification.save
               flash[:alert] = "%{grad}'s certification not saved properly!" % { :grad => graduate.username }
             end
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
      params.require(:training_session).permit(:user_id, :training_id, :course)
    end

    def current_training_session
      @current_training_session = TrainingSession.find(params[:id])
    end

    def changed_params
      params.require(:changed_params).permit(:training_id, :course)
    end

end
