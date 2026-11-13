class StaffNeededCalendar < ApplicationRecord
  belongs_to :space, optional: true

  COLOR_FORMAT = /\A#\h{6}\z/

  normalizes :color, with: ->(color) { color.strip.downcase }

  # The colour is written into style attributes by the calendar pages, so only a #rrggbb value is accepted. A
  # stored value is only checked when it changes, so an older row stays editable for its other fields.
  validates :color, format: { with: COLOR_FORMAT }, allow_blank: true, if: :will_save_change_to_color?

  scope :linked, -> { where.not(calendar_url: "") }
  # The calendars the opening-hours calendar of the home and hours pages shows.
  scope :open_hours, -> { where(role: "open_hours").linked.includes(:space).order(:id) }

  def display_name = name.presence || "Unnamed Calendar"

  # The name the opening-hours calendar shows: its space's, else its own.
  def hours_name = space&.name || display_name

  # The colour its rows and its filter are drawn in: its own, or one made from its link.
  def display_color = color.presence || ApplicationController.helpers.generate_color_from_id(calendar_url.to_s)

  # Its feed's occurrences in the window (a CalendarWindow), as the calendar pages draw them: one source with the
  # calendar's id, colour and rows, or none when the server gave no body.
  def feed_sources(window, name: display_name)
    calendar = ImportedCalendar.load(calendar_url, name: name, color: display_color)
    calendar.fetched? ? [{ id: calendar.id, color: calendar.color, events: calendar.feed_rows(window) }] : []
  end

  # The id the rows of this calendar carry (their groupId), as ImportedCalendar makes it from the link.
  def feed_id = Digest::MD5.hexdigest(calendar_url.to_s)

  validates :role, inclusion: { in: [nil, "", "open_hours"], allow_nil: true }
  validates :space_id, uniqueness: { scope: :role }, if: -> {
 role == "open_hours" }
end
