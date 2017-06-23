class StaffController < StaffAreaController

  def index
    @users = User.all
  end

end
