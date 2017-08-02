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
      redirect_to staff_training_session_path(@new_training_session.id)
    else
      flash[:alert] = "Something went wrong. Please try again."
      redirect_back(fallback_location: root_path)
    end

  end

  def update

    if changed_params['user_id'].present?
      unless @user.admin?
        flash[:alert] = "You're not an admin."
        redirect_back(fallback_location: root_path)
      end
    end

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
      flash[:alert] = "Something went wrong, please try again"
    end

    redirect_back(fallback_location: root_path)
  end

  def certify_trainees
    @current_training_session.users.each do |graduate|
      certification = Certification.new(user_id: graduate.id, training_session_id: @current_training_session.id)
      if certification.save
       flash[:notice] = "#{graduate.username}'s certification has been created"
      else
       flash[:alert] = "#{graduate.username}'s certification not saved properly!"
      end
    end
    redirect_to new_staff_training_session_path
  end

  def destroy
    if @user.admin? && @current_training_session.destroy
        flash[:notice] = "Training session deleted succesfully"
        redirect_to new_staff_training_session_path
    else
        flash[:alert] = "Something went wrong or you're not an admin"
        redirect_back(fallback_location: root_path)
    end
  end

  private

    def default_params
      if params[:user_id].present?
        if @user.admin?
          return {user_id: params[:user_id], training_id: params[:training_id]}
        end
      else
        return {user_id: current_user.id, training_id: params[:training_id]}
      end
    end

    def training_session_params
      params.require(:training_session).permit(:training_id, :course, :users)
    end

    def current_training_session
      @current_training_session = TrainingSession.find(params[:id])
      @staff = User.find(@current_training_session.user_id)
    end

    def changed_params
      params.require(:changed_params).permit(:training_id, :course, :user_id).reject { |_, v| v.blank? }
    end

end
