class VolunteerTasksController < ApplicationController
  before_action :grant_acccess

  private

  def grant_access
    if !current_user.staff?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end
end
