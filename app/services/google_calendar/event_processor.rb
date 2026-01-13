module GoogleCalendar
  class EventProcessor
    VALID_LOCATIONS = ["STM 124", "STM 126"].freeze

    def self.process(event)
      Rails.logger.info "[GCAL] Processing event #{event.id} - #{event.summary}"

      location = event.location.to_s.strip
      return unless VALID_LOCATIONS.include?(location)

      sub_space = SubSpace.find_by!(name: location)

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
        user: User.find_by(email: event.creator.email) ||
              User.find_by(email: "avend029@uottawa.ca")
      )

      booking.save

      return if booking.sub_space_booking_status_id.present?
      status = SubSpaceBookingStatus.new(
        sub_space_booking_id: booking.id,
        booking_status_id: BookingStatus::APPROVED.id
      )    
      status.save

      booking.update(sub_space_booking_status_id: status.id)
    end

    def self.delete_ss_booking(event)
      booking = SubSpaceBooking.find_by(google_booking_id: event.id)
      return unless booking

      booking.update_column(:sub_space_booking_status_id, nil)
      booking.delete
    end
  end
end