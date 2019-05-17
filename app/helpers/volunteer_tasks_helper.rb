module VolunteerTasksHelper

  def return_active(active)
    case active
    when true
      "Yes"
    when false
      "No"
    end
  end
end
