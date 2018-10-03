class StaffAreaController < SessionsController
  before_action :current_user, :ensure_staff
  before_action :default_space

  private

  def ensure_staff
    @user = current_user
    unless @user.staff?
      redirect_to '/' and return
    end
  end

  def default_space
    @space = current_user.lab_sessions&.last&.space || Space.first
  end

end
