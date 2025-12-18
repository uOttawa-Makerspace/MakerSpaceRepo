module GoogleCalendar
  class EventProcessor
    VALID_LOCATIONS = ["STM 124", "STM 126"].freeze

    def self.process(event)
      Rails.logger.info "[GCAL] Processing event #{event.id} - #{event.summary}"

      location = event.location.to_s.strip
      return unless VALID_LOCATIONS.include?(location)

      sub_space = SubSpace.find_by!(name: location)

      if event.status == "cancelled"
        delete_ss_booking(event)
      else
        upsert_ss_booking(event, sub_space)
      end
    end

    def self.upsert_ss_booking(event, sub_space)
      booking =
        SubSpaceBooking.find_or_initialize_by(
          google_booking_id: event.id
        )

      booking.assign_attributes(
        name: event.summary.presence || "Google Calendar Event",
        description: event.description.presence || "No description",
        start_time: event.start.date_time,
        end_time: event.end.date_time,
        sub_space: sub_space,
        blocking: true
      )

      booking.save!

      booking.sub_space_booking_status ||=
        SubSpaceBookingStatus.create!(
          booking_status_id: BookingStatus::PENDING.id,
          sub_space_booking: booking
        )
    end

    def self.delete_ss_booking(event)
      SubSpaceBooking.find_by(
        google_booking_id: event.id
      )&.destroy
    end
  end
end