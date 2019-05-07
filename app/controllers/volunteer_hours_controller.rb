class VolunteerHoursController < VolunteersController
  include VolunteerHoursHelper

  def index
    @user = current_user
    @user_volunteer_hours = VolunteerHour.where(user_id: @user.id).order(created_at: :desc).paginate(:page => params[:page], :per_page => 50)
    @total_hours = calculate_hours(@user_volunteer_hours.pluck(:total_time))
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

  def edit
    @user = current_user
  end

  def destroy
    if VolunteerHour.find(params[:id]).destroy
      flash[:notice] = "Volunteer Hour Deleted"
      redirect_to :back
    else
      flash[:danger] = "Something went wrong"
      redirect_to :back
    end
  end

  private

  def volunteer_hour_params
    params.require(:volunteer_hour).permit(:volunteer_task_id, :date_of_task, :total_time)
  end
end
