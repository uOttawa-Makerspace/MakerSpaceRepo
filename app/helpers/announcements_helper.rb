# frozen_string_literal: true

module AnnouncementsHelper
  def return_active(a)
    if (a.end_date == nil) or (a.end_date >= Date.today)
      case a.active
      when true
        "Yes"
      when false
        "No"
      end
    else
      "Yes but the publishing date is over."
    end
  end

  def return_public(public)
    case public
    when "volunteer"
      "Volunteers"
    when "staff"
      "Staff"
    when "regular_user"
      "Regular Users"
    when "admin"
      "Admins"
    when "all"
      "All Users"
    when "all_visitors"
      "All Visitors (Even not signed in)"
    end
  end
end
