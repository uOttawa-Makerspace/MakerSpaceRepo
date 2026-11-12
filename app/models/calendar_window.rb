# frozen_string_literal: true

# The start and end FullCalendar sends with a feed request. A value with an
# offset (or Z) is an instant; one without is Toronto wall-clock time; a plain
# date is Toronto midnight. A range that is reversed or longer than MAX_SPAN is
# refused with a message the caller can show (400).
class CalendarWindow
  MAX_SPAN = 100.days
  ZONE = RecurrenceRule::ZONE
  OFFSET = /T.*(Z|[+-]\d{2}:?\d{2})\z/i

  class Invalid < StandardError; end

  attr_reader :from, :to

  def self.parse(start_param, end_param)
    new(instant(start_param), instant(end_param))
  end

  def self.instant(value)
    text = value.to_s.strip
    # A blank value parses to nil, which the rescue below reports like any unreadable one.
    (text.match?(OFFSET) ? Time.iso8601(text) : ZONE.parse(text)).in_time_zone(ZONE)
  rescue ArgumentError, NoMethodError
    raise Invalid, I18n.t("errors.calendar.window_invalid")
  end
  private_class_method :instant

  def to_range = from..to

  def initialize(from, to)
    @from = from
    @to = to
    raise Invalid, I18n.t("errors.calendar.window_reversed") if to < from
    raise Invalid, I18n.t("errors.calendar.window_too_long", days: MAX_SPAN.in_days.to_i) if to - from > MAX_SPAN
  end
end
