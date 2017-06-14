class StaffAreaController < SessionsController
  before_action :current_user, :ensure_staff

  private

  def ensure_staff
    @user = current_user
    unless @user.staff?
      redirect_to '/' and return
    end
  end

end
