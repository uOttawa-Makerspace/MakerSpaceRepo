class VolunteerHoursController < VolunteersController
  def index
    @user = current_user
  end

  def new
    @new_volunteer_hour = VolunteerHour.new
    @volunteer_tasks = VolunteerTask.all.order(created_at: :desc).pluck(:title, :id)
  end

  def create
    @volunteer_hour = VolunteerHour.new(volunteer_hour_params)
    @volunteer_hour.user_id = @user.try(:id)
    if @volunteer_hour.save!
      redirect_to new_volunteer_hour_path
      flash[:notice] = "You've successfully sent your volunteer working hours"
    end
  end

  private

  def volunteer_hour_params
    params.require(:volunteer_hour).permit(:volunteer_task_id, :date_of_task, :total_time)
  end
end
