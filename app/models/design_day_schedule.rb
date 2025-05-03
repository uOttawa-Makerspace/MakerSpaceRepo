class DesignDaySchedule < ApplicationRecord
  belongs_to :design_day

  enum :event_for, { student: 0, judge: 1 }, default: :student, validate: true

  # Order by start date then by custom-order
  default_scope { order(start: :desc, ordering: :asc) }

  validates :title_en, presence: true
  validates :title_fr, presence: true
end
