module VolunteerRequestsHelper
  def already_requested?(id)
    if VolunteerRequest.find_by(:user_id => id)
      redirect_to root_path
      flash[:notice] = "You already requested to be a volunteer."
    end
  end
end
