class VolunteerRequestsController < ApplicationController
  def index

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

  end

  private

  def request_params
    params.require(:volunteer_request).permit(:interests)
  end
end
