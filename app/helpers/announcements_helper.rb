# frozen_string_literal: true

module AnnouncementsHelper
  # The announcements bar (partials/_announcements) for the current visitor:
  # [[group, announcement_id, description], ...] in display order, group being
  # :admins, :staff, :all_users, :all_visitors or :volunteers. Cached per user;
  # the key carries the user's roles, today's date (the active scope depends on
  # it) and the collection cache version (newest updated_at and count, so a
  # deletion counts) of the announcements and of the user's dismissals, so a new,
  # edited, deleted or dismissed announcement shows at once. A hit costs those two
  # aggregate queries, which holds only while cache_key_with_version is called on an
  # unloaded, unlimited relation (one COUNT and MAX query each); the query-count spec
  # (announcements_bar_cache_request_spec) guards it. The dismiss forms are NOT
  # cached: their CSRF tokens belong to the current session.
  def visible_announcements
    user = current_user
    admin, staff, volunteer = role_flag(:admin?), role_flag(:staff?), role_flag(:volunteer?)
    dismissed = AnnouncementDismiss.where(user_id: user.id)
    key = ["announcements-bar/v3", user.id || "guest", admin, staff, volunteer, signed_in?, Time.zone.today,
           Announcement.all.cache_key_with_version, dismissed.cache_key_with_version]
    Rails.cache.fetch(key, expires_in: 10.minutes) do
      visible = Announcement.active.where.not(id: dismissed.select(:announcement_id))
      announcement_groups(visible, admin:, staff:, volunteer:).flat_map do |group, scope|
        scope.order(:id).pluck(:id, :description).map { |id, text| [group, id, text] }
      end
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
    if (a.end_date == nil) or (a.end_date >= Time.zone.today)
      case a.active
      when true
        t("admin_pages.common.yes")
      when false
        t("admin_pages.common.no")
      end
    else
      t("admin_pages.announcements.expired")
    end
  end

  # The label of an announcement's audience, or nil for an unknown one.
  def return_public(public)
    t(public, scope: "admin_pages.announcements.audiences") if Announcement::PUBLIC_GOALS.include?(public)
  end

  private

  # The bar's [group, scope of visible announcements] pairs for these roles, in display order.
  def announcement_groups(visible, admin:, staff:, volunteer:)
    groups = []
    groups << [:admins, visible.admins] if admin
    groups << [:staff, visible.staff] if staff
    groups << [:all_users, visible.regular_user] if signed_in?
    groups << [:all_visitors, visible.all_users]
    groups << [:volunteers, visible.volunteers] if volunteer || staff
    groups
  end
end
