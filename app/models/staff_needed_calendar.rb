class StaffNeededCalendar < ApplicationRecord
  belongs_to :space, optional: true
end
