# frozen_string_literal: true

# Gates for the volunteer area. Guests are sent to login; other users are refused.
#   volunteer_access  staff, admins and volunteer-program members
#   staff_access      staff and admins only
module VolunteerAreaAccess
  extend ActiveSupport::Concern

  private

  def volunteer_access
    return signed_in unless signed_in?

    deny_volunteer_area unless current_user.staff? || current_user.volunteer?
  end

  def staff_access
    return signed_in unless signed_in?

    deny_volunteer_area unless current_user.staff?
  end

  def deny_volunteer_area
    flash[:alert] = "You cannot access this area."
    redirect_to root_path
  end
end
