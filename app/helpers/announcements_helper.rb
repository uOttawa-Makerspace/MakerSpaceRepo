module AnnouncementsHelper
  def return_active(active)
    case active
    when true
      return "Yes"
    when false
      return "No"
    end
  end

  def return_public(public)
    case public
    when "volunteer"
      return "Volunteers"
    when "staff"
      return "Staff"
    when "regular_user"
      return "Regular Users"
    when "admin"
      return "Admins"
    end
  end
end
