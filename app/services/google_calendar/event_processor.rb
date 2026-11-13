module GoogleCalendar
  class EventProcessor
    VALID_LOCATIONS = ["STM 124", "STM 126"].freeze
    # Time zone in which an all-day event starts and ends at midnight.
    ALL_DAY_TIME_ZONE = "America/Toronto"

    def self.process(event)
      Rails.logger.info "[GCAL] Processing event #{event.id} - #{event.summary}"

      location = event.location.to_s.strip
      return unless VALID_LOCATIONS.include?(location)

      sub_space = SubSpace.find_by(name: location)
      unless sub_space
        report(ActiveRecord::RecordNotFound.new("No SubSpace named #{location}"), event)
        return
      end

      if event.status == "cancelled" || event.start.nil? || event.end.nil?
        delete_ss_booking(event)
      else
        upsert_ss_booking(event, sub_space)
      end
    end

    # One transaction for the booking and its status; a failed write rolls both back and is reported. Two syncs of the same event cannot both insert it: the
    # unique index on google_booking_id makes the later one wait for the earlier commit and then fail, and it
    # runs again to update the booking the earlier one created.
    def self.upsert_ss_booking(event, sub_space)
      save_in_transaction(event, sub_space)
    rescue ActiveRecord::RecordNotUnique
      save_in_transaction(event, sub_space)
    end

    def self.save_in_transaction(event, sub_space)
      SubSpaceBooking.transaction { save_mirrored_booking(event, sub_space) }
    rescue ActiveRecord::RecordInvalid => e
      report(e, event)
    end

    def self.save_mirrored_booking(event, sub_space)
      booking = SubSpaceBooking.find_or_initialize_by(
        google_booking_id: event.id
      )

      booking.assign_attributes(
        name: event.summary.presence || "Google Calendar Event",
        description: event.description.presence || "No description",
        start_time: event_time(event.start),
        end_time: event_time(event.end),
        sub_space: sub_space,
        blocking: true
      )
      assign_owner(booking, event)

      # A mirror of an event that already exists in Google, so the past-date
      # rule for bookings made in the app does not apply.
      booking.allow_past_start = true
      if booking.booking_status_id.present?
        booking.save!
      else
        booking.save_with_status!(BookingStatus.approved)
      end
    end

    # A timed event has a date_time. An all-day event has only a date (the end date is exclusive in Google's
    # API), which becomes midnight in the makerspace's time zone. Booking times are stored in UTC, as for
    # every other booking.
    def self.event_time(event_date_time)
      return event_date_time.date_time if event_date_time.date_time
      return if event_date_time.date.blank?

      Time.find_zone!(ALL_DAY_TIME_ZONE).parse(event_date_time.date.to_s)
    end

    # Each sync sets the owner to the account it resolves. When it resolves nobody, the stored owner is
    # kept, so a booking imported earlier never loses its owner; a new booking is then imported without one.
    def self.assign_owner(booking, event)
      owner = booking_owner(event)
      booking.user = owner if owner
    end

    # The creator's account, else the account named by the "google_calendar_fallback_email" setting or the
    # GOOGLE_CALENDAR_FALLBACK_EMAIL environment variable, else nobody.
    def self.booking_owner(event)
      User.find_by(email: event.creator&.email) || fallback_owner
    end

    def self.fallback_owner
      email = Setting.get("google_calendar_fallback_email").presence || ENV["GOOGLE_CALENDAR_FALLBACK_EMAIL"].presence
      User.find_by(email: email) if email
    end

    def self.report(error, event)
      Rails.error.report(error, handled: true, context: { google_event_id: event.id })
    end

    def self.delete_ss_booking(event)
      booking = SubSpaceBooking.find_by(google_booking_id: event.id)
      return unless booking

      booking.update_column(:sub_space_booking_status_id, nil)
      booking.delete
    end
  end
end