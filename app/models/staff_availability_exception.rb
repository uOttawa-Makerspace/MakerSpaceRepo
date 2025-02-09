class StaffAvailabilityException < ApplicationRecord
  belongs_to :staff_availability
  validates :covers, :start_at, presence: true

  enum :covers, %i[one_time all_after]
end
