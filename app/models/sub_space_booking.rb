class SubSpaceBooking < ApplicationRecord
  belongs_to :user
  belongs_to :sub_space
  has_one :sub_space_booking_status, dependent: :destroy

  validates :name, presence: true
  validates :description, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
end
