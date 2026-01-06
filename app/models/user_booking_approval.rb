class UserBookingApproval < ApplicationRecord
  belongs_to :user
  belongs_to :staff, class_name: "User", optional: true, foreign_key: "staff_id"

  validates :identity,
            presence: true,
            inclusion: {in: %w[JMTS Staff GNG Other] }

  default_scope { order(created_at: :desc) }
end
