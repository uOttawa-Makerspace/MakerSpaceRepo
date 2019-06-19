module AnnouncementsHelper
  def return_active(active)
    case active
    when true
      return "Yes"
    when false
      return "No"
    end
  end
end
