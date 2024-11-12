class StaffAvailabilityException < ApplicationRecord
  belongs_to :staff_availability
  validates :type, :start_at, presence: true

  enum type: %i[one_time all_after]
end
