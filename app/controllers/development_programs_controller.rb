class DevelopmentProgramsController < ApplicationController
  layout 'development_program'
  before_action :current_user
  # before_action :grant_access

  def index

  end

  def join_volunteer_program
    user = current_user
    user.update_attributes(:role => "volunteer")
    Skill.create(:user_id => user.id)
    flash[:notice] = "You've joined the Volunteer Program"
    redirect_to volunteers_path
  end

  private

  # def grant_access
  #   unless current_user.in_dev_program? || current_user.admin? || current_user.staff?
  #     redirect_to root_path
  #     flash[:alert] = "You cannot access this area."
  #   end
  # end

end
