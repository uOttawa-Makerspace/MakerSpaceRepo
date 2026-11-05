module GoogleCalendar
  class EventProcessor
    VALID_LOCATIONS = ["STM 124", "STM 126"].freeze
    # Owner of a mirrored booking whose Google creator has no account. Configurable with the
    # "google_calendar_fallback_email" setting or the GOOGLE_CALENDAR_FALLBACK_EMAIL environment variable.
    DEFAULT_FALLBACK_EMAIL = "avend029@uottawa.ca"

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

    def self.upsert_ss_booking(event, sub_space)
      booking = SubSpaceBooking.find_or_initialize_by(
        google_booking_id: event.id
      )

      booking.assign_attributes(
        name: event.summary.presence || "Google Calendar Event",
        description: event.description.presence || "No description",
        start_time: event.start.date_time,
        end_time: event.end.date_time,
        sub_space: sub_space,
        blocking: true,
        user: booking_owner(event)
      )

      # A mirror of an event that already exists in Google, so the past-date
      # rule for bookings made in the app does not apply.
      booking.allow_past_start = true
      unless booking.save
        report(ActiveRecord::RecordInvalid.new(booking), event)
        return
      end

      return if booking.sub_space_booking_status_id.present?
      status = SubSpaceBookingStatus.new(
        sub_space_booking_id: booking.id,
        booking_status_id: BookingStatus::APPROVED.id
      )    
      status.save

      booking.update(sub_space_booking_status_id: status.id)
    end

    def self.booking_owner(event)
      User.find_by(email: event.creator&.email) || User.find_by(email: fallback_email)
    end

    def self.fallback_email
      Setting.get("google_calendar_fallback_email").presence ||
        ENV["GOOGLE_CALENDAR_FALLBACK_EMAIL"].presence ||
        DEFAULT_FALLBACK_EMAIL
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