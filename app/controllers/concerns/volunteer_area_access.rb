# frozen_string_literal: true

# Gate for the volunteer area: signed-in staff, admins and volunteer-program
# members. Guests are sent to login; other users are refused.
module VolunteerAreaAccess
  extend ActiveSupport::Concern

  private

  def volunteer_access
    return signed_in unless signed_in?

    if !current_user.staff? && !current_user.volunteer?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end
end
