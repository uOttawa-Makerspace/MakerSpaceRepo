class VolunteerTasksController < ApplicationController
  layout 'volunteer'
  before_action :grant_access

  def index
    @volunteer_tasks = VolunteerTask.all.order(created_at: :desc).paginate(:page => params[:page], :per_page => 50)
  end

  private

  def grant_access
    if !current_user.staff?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end
end
