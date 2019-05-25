class VolunteerRequestsController < ApplicationController
  layout 'volunteer'
  before_action :grant_access, only: [:index, :show]
  def index
    @volunteer_requests = VolunteerRequest.all.order(created_at: :desc).paginate(:page => params[:page], :per_page => 50)
  end

  def create
    @volunteer_request = VolunteerRequest.new(request_params)
    @volunteer_request.user_id = current_user.id
    if @volunteer_request.save!
      redirect_to root_path
      flash[:notice] = "You've successfully submitted your volunteer request."
    end
  end

  def show
    @volunteer_request = VolunteerRequest.find(params[:id])
    @user = @volunteer_request.user
    @certifications = @user.certifications
  end

  def update_approval
    volunteer_request = VolunteerRequest.find(params[:id])
    if volunteer_request.update_attributes(:approval => params[:approval])
      flash[:notice] = "Volunteer Request updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to volunteer_requests_path
  end

  private

  def grant_access
    if !current_user.staff?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end

  def request_params
    params.require(:volunteer_request).permit(:interests)
  end
end
