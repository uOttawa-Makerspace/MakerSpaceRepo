class VolunteerTasksController < ApplicationController
  layout 'volunteer'
  before_action :grant_access

  def index
    @volunteer_tasks = VolunteerTask.all.order(created_at: :desc).paginate(:page => params[:page], :per_page => 50)
  end

  def edit

  end

  def destroy
    volunteer_task = VolunteerHour.find(params[:id])
    if volunteer_task.destroy
      flash[:notice] = "Volunteer Task Deleted"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to volunteer_hours_path
  end

  private

  def grant_access
    if !current_user.staff?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end
end
