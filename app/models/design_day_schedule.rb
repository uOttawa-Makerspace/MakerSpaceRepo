class DesignDaySchedule < ApplicationRecord
  belongs_to :design_day

  enum :event_for, { student: 0, judge: 1 }, default: :student, validate: true

  # Order by start date then by custom-order
  default_scope { order(:event_for, ordering: :asc, start: :asc) }

  validates :ordering,
            comparison: {
              greater_than_or_equal_to: 0
            },
            allow_nil: true
  validates :title_en, presence: true
  validates :title_fr, presence: true
end
