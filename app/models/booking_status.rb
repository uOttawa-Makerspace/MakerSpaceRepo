class BookingStatus < ApplicationRecord
  # A status that bookings still use cannot be destroyed; nothing is deleted or cleared.
  has_many :sub_space_bookings, dependent: :restrict_with_error
  has_many :sub_space_booking_statuses, dependent: :restrict_with_error
  validates :name, presence: true, uniqueness: true

  # The three reference rows, looked up by name each time they are needed. A
  # class-level constant would be read while the class loads, which is before
  # the rows exist on a fresh database.
  def self.pending = find_by!(name: "Pending")
  def self.approved = find_by!(name: "Approved")
  def self.declined = find_by!(name: "Declined")
end
