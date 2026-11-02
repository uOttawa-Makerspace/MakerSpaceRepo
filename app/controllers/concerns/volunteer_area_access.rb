# frozen_string_literal: true

# Role gate for the volunteer area: staff, admins and volunteer-program members.
module VolunteerAreaAccess
  extend ActiveSupport::Concern

  private

  def volunteer_access
    if !current_user.staff? && !current_user.volunteer?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end
end
