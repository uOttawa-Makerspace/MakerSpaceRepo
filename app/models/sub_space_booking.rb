class SubSpaceBooking < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :sub_space
  belongs_to :recurring_booking, optional: true
  has_one :sub_space_booking_status,
          dependent: :destroy
  validates :name, presence: true
  validates :description, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :end_time_after_start_time

  COLOR_LEGEND = [
    {
      id: "your_pending_bookings",
      name: "Your Pending Bookings",
      color: "#B5A500"
    },
    {
      id: "your_confirmed_bookings",
      name: "Your Confirmed Bookings",
      color: "#49794b"
    },
    {
      id: "other_pending_bookings",
      name: "Other Pending Bookings",
      color: "#FFA500"
    },
    {
      id: "other_confirmed_bookings",
      name: "Other Confirmed Bookings",
      color: "#497979"
    },
    { id: "blocking_booking", name: "Blocking Bookings", color: "#ABABABFF" }
  ]

  def end_time_after_start_time
    return unless start_time.present? && end_time.present? && start_time >= end_time
      errors.add(:expiration_date, "Start Time needs to be before end time")
    
  end

  def self.color_legend
    COLOR_LEGEND
  end

  def color(current_user_id)
    status =
      if blocking
        "blocking_booking"
      elsif SubSpaceBookingStatus.find(
            sub_space_booking_status_id
          ).booking_status_id == BookingStatus::APPROVED.id
        if user_id == current_user_id
          "your_confirmed_bookings"
        else
          "other_confirmed_bookings"
        end
      elsif user_id == current_user_id
        "your_pending_bookings"
        else
          "other_pending_bookings"
      end
    COLOR_LEGEND.find { |c| c[:id] == status }[:color]
  end

  def create_bookings_from_ics
    # Filter all CEED Space events into the ones for STEM124 and the ones for STEM126
    @staff_needed_calendars = StaffNeededCalendar.all.find_by(space_id: 24)
    @staff_needed_calendars.each do |snc|
      @events = parse_ics_calendar(snc.calendar_url, "Imported ICS Calendar")
      # Arrays for each rooms' events
      @events_124 = []
      @events_126 = []
      @events.each do |event|
        if event.location == "STEM124"
          @events_124 << event
        elsif event.location == "STEM126"
          @events_126 << event
        end
      end
    end
    
    # Creating the bookings
    @events_124.each do |event|
      create SubSpaceBooking(
        start_time: event.start,
        end_time: event.end,
        name: event.name,
        description: event.description,
        sub_space_id: 10,
        blocking: true
      )
    end

    # Creating the bookings
    @events_126.each do |event|
      create SubSpaceBooking(
        start_time: event.start,
        end_time: event.end,
        name: event.name,
        description: event.description,
        sub_space_id: 11,
        blocking: true
      )
    end
  end
end
