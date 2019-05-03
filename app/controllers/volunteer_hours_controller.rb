class VolunteerHoursController < VolunteersController
  def index
    @user = current_user
  end
end
