class UserBookingApproval < ApplicationRecord
  belongs_to :user
  belongs_to :staff, class_name: "User", optional: true, foreign_key: "staff_id"

  validates :identity, presence: true

  BOOKING_SUPERVISORS = %w[Avend029 jasondemers jboud030 lionelregis]
end
