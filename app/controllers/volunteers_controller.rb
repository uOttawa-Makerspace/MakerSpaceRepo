class VolunteersController < ApplicationController
  layout 'volunteer'
  before_action :current_user
  before_action :grant_access
  def index
    @user = current_user
  end

  private

  def grant_access
    if current_user.volunteer? || current_user.admin? || current_user.staff?
      flash.now[:notice] = "You are in the Volunteer Area."
    else
      redirect_to root_path
      flash[:alert] = "You cannot access this area."
    end
  end
end
