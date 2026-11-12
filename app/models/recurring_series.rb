# frozen_string_literal: true

# A repeating calendar entry, expanded into the occurrences that fall in a
# window. Timed series keep their exact length across a clock change; all-day
# series advance by calendar days. Exclusions are instants. Only #starts_between
# names the repeat library (the rrule gem), so the library can be swapped there.
#
# A series repeats a wall-clock time in the zone of its start (Toronto for
# stored records): a nonexistent time moves forward (02:30 on a spring-forward
# day is 03:30), a time in the repeated hour is listed once, at its first
# instant, and COUNT counts it once. A rule finer than daily is refused
# (UnsupportedRule): the validator has never allowed one, and none is stored.
class RecurringSeries
  ZONE = RecurrenceRule::ZONE
  SUB_DAILY = /FREQ=(SECONDLY|MINUTELY|HOURLY)/
  # An UNTIL with no Z: a date, or a date and a time.
  LOCAL_UNTIL = /UNTIL=(?<date>\d{8})(?<time>(?>(?:T\d{6})?))(?![\dZ])/

  class UnsupportedRule < ArgumentError; end

  Occurrence = Data.define(:starts_at, :ends_at, :original_start, :all_day, :override)
  Result = Data.define(:occurrences, :truncated)

  # `record` is an Event or StaffUnavailability.
  def self.for_record(record)
    new(rule: record.recurrence_rule, starts_at: record.start_time.in_time_zone(ZONE), ends_at: record.end_time)
  end

  # `starts_at` is a TimeWithZone; the series repeats the wall time of its zone.
  # Exclusions are the rule's own EXDATE lines, read as instants.
  def initialize(rule:, starts_at:, ends_at:)
    finer = rule.to_s[SUB_DAILY, 1]
    raise UnsupportedRule, "repeat rules finer than daily are not supported: #{finer}" if finer

    @rule = rule
    @starts_at = starts_at
    @zone = starts_at.time_zone
    @excluded = RecurrenceRule.exdate_instants(rule)
    measure(ends_at.in_time_zone(@zone))
    # The gem repeats wall times and resolves the second of two equal ones to the first instant.
    @gem_start = @zone.local(*starts_at.to_a[0, 6].reverse)
  end

  # `window` is a Range of instants (CalendarWindow#to_range).
  # Occurrences that start in the window (the /api/v1 and staff app contract).
  def occurrences_starting_in(window, limit:)
    collect(starts_between(window.begin, window.end), limit)
  end

  # Occurrences that overlap the window, including one that began before it.
  def occurrences_overlapping(window, limit:)
    overlapping = starts_between(window.begin - @lookback, window.end)
                  .select { |start| ends_at(start) > window.begin && start < window.end }
    collect(overlapping, limit)
  end

  private

  # What a start needs to become an occurrence: all-day or not, how far it reaches,
  # and how far back an occurrence can start and still overlap a window.
  def measure(ends_at)
    @all_day = CalendarTime.all_day?(@starts_at, ends_at)
    @span = @all_day ? { days: 1 } : { seconds: ends_at - @starts_at }
    @lookback = ends_at(@starts_at) - @starts_at + 1.hour
  end

  def collect(starts, limit)
    found = starts.first(limit + 1).map { |start| occurrence(start) }
    Result.new(occurrences: found.first(limit), truncated: found.size > limit)
  end

  def occurrence(start)
    Occurrence.new(starts_at: start, ends_at: ends_at(start), original_start: start, all_day: @all_day, override: nil)
  end

  def ends_at(start) = start.advance(@span)

  # The only method that reaches the repeat library. Lazy: the caller's
  # first(limit + 1) stops the walk. The gem takes COUNT from its start, so the
  # series start is the gem's; only a series that starts at the second 01:30 of a
  # fall-back night needs the explicit mapping below, because the gem resolves
  # that wall time to the first instant and would otherwise drop the start.
  def starts_between(from, to)
    rule = RRule::Rule.new(rule_body, dtstart: @gem_start, tzid: @zone.tzinfo.name, max_year: to.year + 1)
    rule.each(floor_date: from + (@gem_start - @starts_at)).lazy
        .take_while { |time| time <= to }
        .map { |time| time == @gem_start ? @starts_at : time.in_time_zone(@zone) }
        .select { |time| time >= from && !@excluded.include?(time.to_i) }
  end

  # The bare rule body, with a UNTIL that has no Z read in the series zone: a date
  # means the end of that day, a time is wall time.
  def rule_body
    RecurrenceRule.rule_body(@rule).sub(LOCAL_UNTIL) do
      match = Regexp.last_match
      "UNTIL=#{@zone.parse("#{match[:date]}#{match[:time].presence || 'T235959'}").utc.strftime(RecurrenceRule::STAMP)}"
    end
  end
end
