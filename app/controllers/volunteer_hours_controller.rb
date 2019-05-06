class VolunteerHoursController < VolunteersController
  def index
    @user = current_user
  end

  def new
    @new_volunteer_hour = VolunteerHour.new
    @volunteer_tasks = VolunteerTask.all.order(created_at: :desc).pluck(:id, :title)
  end

  def create

  end
end
