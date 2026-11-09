class UserBookingApproval < ApplicationRecord
  belongs_to :user
  belongs_to :staff, class_name: "User", optional: true, foreign_key: "staff_id"

  IDENTITIES = %w[JMTS Staff GNG Other].freeze

  validates :identity,
            presence: true,
            inclusion: {in: IDENTITIES }

  default_scope { order(created_at: :desc) }
end
