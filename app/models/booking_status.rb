class BookingStatus < ApplicationRecord
  has_many :booking_statuses, dependent: :destroy
  validates :name, presence: true, uniqueness: true

  PENDING = BookingStatus.find_by(name: "Pending")
  APPROVED = BookingStatus.find_by(name: "Approved")
  DECLINED = BookingStatus.find_by(name: "Declined")
end
