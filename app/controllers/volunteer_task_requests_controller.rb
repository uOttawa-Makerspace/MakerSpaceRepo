class VolunteerTaskRequestsController < ApplicationController
  layout 'volunteer'

  def index
    current_user.staff? ? @volunteer_task_requests = VolunteerTaskRequest.all : @volunteer_task_requests = current_user.volunteer_task_requests
    @total_volunteers = User.where(role: "volunteer").count
    @pending_volunteer_task_requests = @volunteer_task_requests.not_processed.includes(:volunteer_task).order(created_at: :desc).paginate(:page => params[:page], :per_page => 15)
    @processed_volunteer_task_requests = @volunteer_task_requests.processed.includes(:volunteer_task).order(created_at: :desc).paginate(:page => params[:page], :per_page => 15)
  end

  def create_request
    volunteer_task = VolunteerTask.find(params[:id])
    volunteer_task_request = VolunteerTaskRequest.new
    volunteer_task_request.volunteer_task_id = volunteer_task.id
    volunteer_task_request.user_id = current_user.id
    if volunteer_task_request.save
      MsrMailer.send_notification_for_task_request(volunteer_task.id, volunteer_task_request.user_id).deliver
      flash[:notice] = "You've sent a request. No further action is needed."
    else
      flash[:notice] = "Something went wrong. Please try it again."
    end
    redirect_to :back
  end

  def update_approval
    volunteer_task_request = VolunteerTaskRequest.find(params[:id])
    if volunteer_task_request.update_attributes(:approval => params[:approval])
      volunteer_task_join = volunteer_task_request.volunteer_task_join
      volunteer_task_join.update_attributes(active: false)
      if volunteer_task_request.approval
        volunteer_task = volunteer_task_request.volunteer_task
        volunteer_id = volunteer_task_request.user_id
        volunteer = volunteer_task_request.user
        volunteer.update_wallet
        CcMoney.create_cc_money_from_approval(volunteer_task.id, volunteer_id, volunteer_task.cc)
        volunteer.update_wallet
        VolunteerHour.create_volunteer_hour_from_approval(volunteer_task.id, volunteer_id, volunteer_task.hours)
      end
      MsrMailer.send_notification_for_task_request_update(volunteer_task_request.id).deliver
      flash[:notice] = "Task request updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to volunteer_task_requests_path
  end

end
