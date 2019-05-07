module VolunteerHoursHelper
  def calculate_hours(volunteer_hours)
    return volunteer_hours.sum
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
end
