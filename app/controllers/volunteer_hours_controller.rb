class VolunteerHoursController < VolunteersController
  def index
    @user = current_user
  end

  def new
    @new_volunteer_hour = VolunteerHour.new
  end

  def create

  end
end
