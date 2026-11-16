module SubSpaceBookingHelper
  # The room's booking rules, as phrases that follow the room's name on its calendar.
  def booking_rules(room)
    rules = []
    if room.maximum_booking_duration.present?
      rules << t("sub_space_booking.rules.maximum_duration", hours: room.maximum_booking_duration)
    end
    if room.maximum_booking_hours_per_week.present?
      rules << t("sub_space_booking.rules.weekly_hours", hours: room.maximum_booking_hours_per_week)
    end
    rules << t("sub_space_booking.rules.public_by_default") if room.default_public
    rules << booking_approval_rule(room) if room.approval_required
    rules
  end

  private

  def booking_approval_rule(room)
    if room.max_automatic_approval_hour.present?
      t("sub_space_booking.rules.approval_with_automatic", hours: room.max_automatic_approval_hour)
    else
      t("sub_space_booking.rules.approval_required")
    end
  end
end
