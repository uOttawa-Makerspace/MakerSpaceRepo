# frozen_string_literal: true

module VolunteerHoursHelper
  def calculate_hours(volunteer_hours)
    volunteer_hours.sum
  end

  def return_approval(approval)
    case approval
    when nil
      "Not Accessed"
    when true
      "Approved"
    when false
      "Not Approved"
    end
  end

  # Staff go back to the requests page; every other volunteer to their own hours.
  def define_redirect(user)
    if user.staff?
      redirect_to volunteer_hour_requests_volunteer_hours_path
    else
      redirect_to volunteer_hours_path
    end
  end
end
