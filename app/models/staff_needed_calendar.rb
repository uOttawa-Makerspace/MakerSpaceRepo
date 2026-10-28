class StaffNeededCalendar < ApplicationRecord
  belongs_to :space, optional: true

  validates :role, inclusion: { in: [nil, "", "open_hours"], allow_nil: true }
  validates :space_id, uniqueness: { scope: :role, message: "can only have one open_hours calendar" }, if: -> {
 role == "open_hours" }
end
