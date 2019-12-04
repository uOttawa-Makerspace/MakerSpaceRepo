class VolunteerTaskRequestsController < ApplicationController
  layout 'volunteer'

  def index
    current_user.staff? ? @volunteer_task_requests = VolunteerTaskRequest.all : @volunteer_task_requests = current_user.volunteer_task_requests
    @total_volunteers = User.where(role: "volunteer").count
    @pending_volunteer_task_requests = @volunteer_task_requests.not_processed.order(created_at: :desc).paginate(:page => params[:page], :per_page => 15)
    @processed_volunteer_task_requests = @volunteer_task_requests.processed.order(created_at: :desc).paginate(:page => params[:page], :per_page => 15)
  end

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

  def update_approval
    volunteer_task_request = VolunteerTaskRequest.find(params[:id])
    if volunteer_task_request.update_attributes(:approval => params[:approval])
      volunteer_task_join = volunteer_task_request.volunteer_task.volunteer_task_join
      volunteer_task_join.update_attributes(active: false)
      flash[:notice] = "Task request updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to volunteer_task_requests_path
  end

end
