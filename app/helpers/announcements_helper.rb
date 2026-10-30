# frozen_string_literal: true

module AnnouncementsHelper
  # The announcements bar (partials/_announcements) for the current visitor:
  # [[group, announcement_id, description], ...] in display order, group being
  # :admins, :staff, :all_users, :all_visitors or :volunteers. Cached per user;
  # the key carries the user's roles, today's date (the active scope depends on
  # it) and the collection cache version (newest updated_at and count, so a
  # deletion counts) of the announcements and of the user's dismissals, so a new,
  # edited, deleted or dismissed announcement shows at once. A hit costs those two aggregate queries. The
  # dismiss forms are NOT cached: their CSRF tokens belong to the current session.
  def visible_announcements
    user = current_user
    admin, staff, volunteer = role_flag(:admin?), role_flag(:staff?), role_flag(:volunteer?)
    dismissed = AnnouncementDismiss.where(user_id: user.id)
    key = ["announcements-bar/v2", user.id || "guest", admin, staff, volunteer, signed_in?, Time.zone.today,
           Announcement.all.cache_key_with_version, dismissed.cache_key_with_version]
    Rails.cache.fetch(key, expires_in: 10.minutes) do
      visible = Announcement.active.where.not(id: dismissed.select(:announcement_id))
      groups = []
      groups << [:admins, visible.admins] if admin
      groups << [:staff, visible.staff] if staff
      groups << [:all_users, visible.all_users] if signed_in? && Announcement.active.regular_user.exists?
      groups << [:all_visitors, visible.all_users]
      groups << [:volunteers, visible.volunteers] if volunteer || staff
      groups.flat_map { |group, scope| scope.order(:id).pluck(:id, :description).map { |id, text| [group, id, text] } }
    end
  end

  ANNOUNCEMENT_BAR_STYLES = {
    admins: ["alert-secondary", "To Admins:"],
    staff: ["alert-info", "To Staff:"],
    all_users: ["alert-primary", "To All Users: "],
    all_visitors: ["alert-primary", "To All Visitors: "],
    volunteers: ["alert-warning", "To Volunteers:"]
  }.freeze
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
      "All Users"
    when "admin"
      "Admins"
    when "all"
      "All Visitors (Even not signed in)"
    end
  end
end
