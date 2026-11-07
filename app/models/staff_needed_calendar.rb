class StaffNeededCalendar < ApplicationRecord
  belongs_to :space, optional: true

  COLOR_FORMAT = /\A#\h{6}\z/

  normalizes :color, with: ->(color) { color.strip.downcase }

  # The colour is written into style attributes by the calendar pages, so only a #rrggbb value is accepted. A
  # stored value is only checked when it changes, so an older row stays editable for its other fields.
  validates :color, format: { with: COLOR_FORMAT }, allow_blank: true, if: :will_save_change_to_color?

  validates :role, inclusion: { in: [nil, "", "open_hours"], allow_nil: true }
  validates :space_id, uniqueness: { scope: :role }, if: -> {
 role == "open_hours" }
end
