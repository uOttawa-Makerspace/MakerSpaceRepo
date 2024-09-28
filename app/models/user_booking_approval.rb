class UserBookingApproval < ApplicationRecord
  belongs_to :user
  belongs_to :staff, class_name: "User", optional: true, foreign_key: "staff_id"

  validates :identity, presence: true

  default_scope { order(created_at: :desc) }
end
