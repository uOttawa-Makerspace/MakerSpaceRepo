# frozen_string_literal: true

# The span of time a calendar page asks a feed for: FullCalendar's `start` and `end` params. A time with an offset
# is that instant, a time without one is Toronto wall time, and a date alone is Toronto midnight. A window is at
# most Event::MAX_FEED_RANGE long. A request with neither param gets ALL, which keeps everything (a caller that
# wants every record).
#
# What a window keeps: a one-off that overlaps it (an end at its start included), and every series that starts
# before its end, because the page still repeats a series itself.
class CalendarWindow
  # Its message is the answer shown to the caller.
  class Invalid < StandardError; end

  # The window of a request with neither param: it keeps everything.
  class Unbounded
    def records(relation) = relation
    def entries(list) = list
  end

  ALL = Unbounded.new

  attr_reader :from, :to

  def self.from_params(params)
    return ALL if params[:start].blank? && params[:end].blank?

    new(parse(params[:start]), parse(params[:end]))
  end

  # The time, or nil when the value is not one.
  def self.parse(value)
    RecurrenceRule::ZONE.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def initialize(from, to)
    raise Invalid, I18n.t("errors.calendar.window_invalid") unless from && to && from <= to
    raise Invalid, I18n.t("errors.calendar.window_too_long", days: Event::MAX_FEED_RANGE.in_days.to_i) if Event.feed_range_too_long?(from, to)

    @from = from
    @to = to
  end

  # The events or unavailabilities of `relation` the window keeps.
  def records(relation)
    table = relation.arel_table
    relation.where(table[:start_time].lt(to)).where(table[:end_time].gteq(from).or(table[:recurrence_rule].not_eq("")))
  end

  # The imported calendar entries (ImportedCalendar::Entry) the window keeps.
  def entries(list)
    list.select { |entry| entry.series || overlaps?(entry.starts_at, entry.ends_at) }
  end

  private

  # An entry with no end is a moment at its start.
  def overlaps?(starts_at, ends_at)
    starts_at < to && (ends_at || starts_at) >= from
  end
end
