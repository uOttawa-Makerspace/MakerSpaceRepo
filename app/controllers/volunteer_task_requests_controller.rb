class VolunteerTaskRequestsController < ApplicationController

  def create_request
    volunteer_task = VolunteerTask.find(params[:id])
    volunteer_task_request = VolunteerTaskRequest.new
    volunteer_task_request.volunteer_task_id = volunteer_task.id
    volunteer_task_request.user_id = current_user.id
    if volunteer_task_request.save
      flash[:notice] = "You've sent a request. No further action is needed."
    else
      flash[:notice] = "Something went wrong. Please try it again."
    end
    redirect_to :back
  end

end
