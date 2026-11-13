class StaffNeededCalendar < ApplicationRecord
  belongs_to :space, optional: true

  validates :role, inclusion: { in: [nil, "", "open_hours"], allow_nil: true }
  validates :space_id, uniqueness: { scope: :role }, if: -> {
 role == "open_hours" }
end
