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
end
