# frozen_string_literal: true

# Gates for the volunteer area. Guests are sent to login; other users are refused.
#   volunteer_access  staff, admins and volunteer-program members
#   staff_access      staff and admins only
module VolunteerAreaAccess
  extend ActiveSupport::Concern

  included do
    require_authorization
  end

  private

  def volunteer_access
    return signed_in unless signed_in?

    if current_user.staff? || current_user.volunteer?
      record_authorization!(:volunteer)
    else
      deny_volunteer_area
    end
  end

  def staff_access
    return signed_in unless signed_in?

    if current_user.staff?
      record_authorization!(:staff)
    else
      deny_volunteer_area
    end
  end

  def deny_volunteer_area
    flash[:alert] = "You cannot access this area."
    redirect_to root_path
  end
end
