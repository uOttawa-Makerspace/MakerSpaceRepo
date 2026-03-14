class Staff::TapBoxConsoleController < StaffAreaController
  before_action :signed_in
  before_action :grant_access

  def show
    @logs = TapBoxLog.recent.includes(:user, :space)
  end

  private

  def grant_access
    unless current_user.staff?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end
end