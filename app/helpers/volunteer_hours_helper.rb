# frozen_string_literal: true

module VolunteerHoursHelper
  def calculate_hours(volunteer_hours)
    volunteer_hours.sum
  end

  def return_approval(approval)
    case approval
    when nil
      'Not Accessed'
    when true
      'Approved'
    when false
      'Not Approved'
    end
  end

  def define_redirect(role)
    if role == 'volunteer'
      redirect_to volunteer_hours_path
    else
      redirect_to volunteer_hour_requests_volunteer_hours_path
    end
  end
end
