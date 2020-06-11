# frozen_string_literal: true

module AnnouncementsHelper
  def return_active(active)
    case active
    when true
      'Yes'
    when false
      'No'
    end
  end

  def return_public(public)
    case public
    when 'volunteer'
      'Volunteers'
    when 'staff'
      'Staff'
    when 'regular_user'
      'Regular Users'
    when 'admin'
      'Admins'
    when 'all'
      'All Users'
    end
  end
end
