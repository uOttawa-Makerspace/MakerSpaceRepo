class Staff::TrainingSessionsController < StaffAreaController

  before_action :current_training_session, only: [:show, :edit, :update, :certify_trainees, :destroy]
  before_action :changed_params, only: [:update]

  layout 'staff_area'

  def index

  end

  def new
    @new_training_session = TrainingSession.new
  end

  def create
    @new_training_session = TrainingSession.new(default_params)
    if params['training_session_users'].present?
      params['training_session_users'].each do |user_id|
        @new_training_session.users << User.find(user_id)
      end
    end
    if @new_training_session.save
      redirect_to "#{staff_training_session_path(@new_training_session.id)}"
    else
      redirect_to :back
      flash[:alert] = "Something went wrong. Please try again."
    end
  end

  def update
    @current_training_session.update(changed_params)

    if params['dropped_users'].present?
        @current_training_session.users -= User.where(username: params['dropped_users'])
    end

    if params['added_users'].present?
      @current_training_session.users +=  User.where(username: params['added_users'])
    end

    @current_training_session.users = @current_training_session.users.uniq

    if @current_training_session.save
      flash[:notice] = "Training session updated succesfully"
    else
      flash[:aler] = "Something went wrong, please try again"
    end
    redirect_to :back
  end

  def certify_trainees
    staff = current_user
    if params['training_session_graduates'].present?
      params['training_session_graduates'].each do |graduate|
         if @current_training_session.users.include? User.find(graduate)
           unless User.find(graduate).certifications.include? Certification.find_by(training_session_id: @current_training_session.id)
             certification = Certification.new(user_id: graduate, training_session_id: @current_training_session.id)
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

  def destroy
    if @current_training_session.destroy
        flash[:notice] = "Training session deleted succesfully"
    end
    redirect_to :back
  end

  private

    def default_params
      return {user_id: current_user.id, training_id: Training.all.first.id}
    end

    def training_session_params
      params.require(:training_session).permit(:training_id, :course, :users)
    end

    def current_training_session
      @current_training_session = TrainingSession.find(params[:id])
    end

    def changed_params
      params.require(:changed_params).permit(:training_id, :course)
    end

end
