# frozen_string_literal: true

# The start and end FullCalendar sends with a feed request. A value with an
# offset (or Z) is an instant; one without is Toronto wall-clock time; a plain
# date is Toronto midnight. A range that is reversed or longer than MAX_SPAN is
# refused with a message the caller can show (400).
class CalendarWindow
  MAX_SPAN = 100.days
  ZONE = RecurrenceRule::ZONE

  class Invalid < StandardError; end

  attr_reader :from, :to

  def self.parse(start_param, end_param)
    new(instant(start_param), instant(end_param))
  end

  # ZONE.parse reads an offset or Z as that instant, and a value without one as Toronto wall time.
  def self.instant(value)
    ZONE.parse(value.to_s.strip).in_time_zone(ZONE)
  rescue ArgumentError, NoMethodError # a blank value parses to nil
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
