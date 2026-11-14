class SubSpace < ApplicationRecord
  belongs_to :space
  has_many :sub_space_bookings, dependent: :restrict_with_error, foreign_key: :sub_space_id

  validates :name, presence: true

  # The room's booking rules, as phrases that follow the room's name on its calendar.
  def booking_rules
    rules = []
    rules << "has a maximum booking duration of #{maximum_booking_duration} hours" if maximum_booking_duration.present?
    if maximum_booking_hours_per_week.present?
      rules << "has a maximum booking hours per person per week of #{maximum_booking_hours_per_week} hours"
    end
    rules << "bookings (Name and Description of event) are public by default" if default_public
    rules << approval_rule if approval_required
    rules
  end

  private

  def approval_rule
    if max_automatic_approval_hour.present?
      "Bookings require manual approval, bookings of #{max_automatic_approval_hour} hours or less will be automatically approved"
    else
      "bookings will require manual approval"
    end
  end
end
