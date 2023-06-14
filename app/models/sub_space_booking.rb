class SubSpaceBooking < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :sub_space, foreign_key: :sub_space_id
  has_one :sub_space_booking_status,
          dependent: :destroy,
          foreign_key: :sub_space_booking_id
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
    if start_time.present? && end_time.present? && start_time >= end_time
      errors.add(:expiration_date, "Start Time needs to be before end time")
    end
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
      else
        if user_id == current_user_id
          "your_pending_bookings"
        else
          "other_pending_bookings"
        end
      end
    COLOR_LEGEND.find { |c| c[:id] == status }[:color]
  end
end
