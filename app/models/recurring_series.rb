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
  SUB_DAILY = /FREQ=(SECONDLY|MINUTELY|HOURLY)/i
  # An UNTIL with no Z: a date, or a date and a time.
  LOCAL_UNTIL = /UNTIL=(?<date>\d{8})(?<time>(?>(?:T\d{6})?))(?![\dZ])/i

  # A walk never goes on longer than this past where it starts (and never past the window): it bounds a rule that
  # never matches (a 30th of February), whatever window was asked for.
  MAX_YEARS = 100
  DAYS = ->(from, to) { (to.to_date - from.to_date).to_i }
  MONTHS = ->(from, to) { ((to.year - from.year) * 12) + to.month - from.month }
  # FREQ => the unit a period is counted in, how many units one period is, and how to count them between two times.
  PERIODS = { "DAILY" => [:days, 1, DAYS], "WEEKLY" => [:days, 7, DAYS],
              "MONTHLY" => [:months, 1, MONTHS], "YEARLY" => [:months, 12, MONTHS] }.freeze
  NO_SHIFT = [:days, 1, ->(*) { 0 }].freeze

  class UnsupportedRule < ArgumentError; end

  Occurrence = Data.define(:starts_at, :ends_at, :all_day)
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

  # Occurrences that start in the window, a Range of instants (the /api/v1 and staff app contract).
  def occurrences_starting_in(window, limit:)
    collect(starts_between(window.begin, window.end), limit)
  end

  private

  # What a start needs to become an occurrence: all-day or not, and how far it reaches.
  def measure(ends_at)
    @all_day = CalendarTime.all_day?(@starts_at, ends_at)
    @span = @all_day ? { days: 1 } : { seconds: ends_at - @starts_at }
  end

  def collect(starts, limit)
    found = starts.first(limit + 1).map { |start| Occurrence.new(starts_at: start, ends_at: ends_at(start), all_day: @all_day) }
    Result.new(occurrences: found.first(limit), truncated: found.size > limit)
  end

  def ends_at(start) = start.advance(@span)

  # The only method that reaches the repeat library. Lazy: the caller's
  # first(limit + 1) stops the walk. The gem takes COUNT from its start, so the
  # series start is the gem's; only a series that starts at the second 01:30 of a
  # fall-back night needs the explicit mapping below, because the gem resolves
  # that wall time to the first instant and would otherwise drop the start.
  def starts_between(from, to)
    body = rule_body
    start = walk_start(from, body)
    rule = RRule::Rule.new(body, dtstart: start, tzid: @zone.tzinfo.name, max_year: [start.year + MAX_YEARS, to.year + 1].min)
    rule.each(floor_date: from + (@gem_start - @starts_at)).lazy
        .take_while { |time| time <= to }
        .map { |time| time == @gem_start ? @starts_at : time.in_time_zone(@zone) }
        .select { |time| time >= from && !@excluded.include?(time.to_i) }
  end

  # Where the gem starts walking: the series start with COUNT (the count is taken from it). Without, the
  # start moves forward by whole periods in the series zone to a little before `from` (same wall time and
  # phase, so the same occurrences); a start the move cannot keep (the 31st, a skipped time) goes back a period.
  def walk_start(from, body)
    unit, size, elapsed = PERIODS.fetch(body[/FREQ=(\w+)/i, 1].to_s.upcase, NO_SHIFT)
    step = size * [body[/INTERVAL=(\d+)/i, 1].to_i, 1].max
    periods = body.match?(/COUNT=/i) ? 0 : (elapsed.call(@gem_start, from) / step) - 1
    periods.downto(1) do |count|
      shifted = @gem_start.advance(unit => count * step)
      return shifted if shifted.advance(unit => -count * step) == @gem_start
    end
    @gem_start
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
