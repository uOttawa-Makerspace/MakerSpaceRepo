# frozen_string_literal: true

# A repeating calendar entry, expanded into the occurrences that fall in a
# window. Timed series keep their exact length across a clock change; all-day
# series advance by calendar days. Exclusions are instants. Only #starts_between
# names the repeat library (the rrule gem), so the library can be swapped there.
#
# A series repeats a wall-clock time in the zone of its start (Toronto for
# stored records): a nonexistent time moves
# forward (02:30 on a spring-forward day is 03:30), a time in the repeated hour
# is listed once, at its first instant, and COUNT counts it once.
class RecurringSeries
  ZONE = RecurrenceRule::ZONE
  ELAPSED_TIME = /FREQ=(SECONDLY|MINUTELY|HOURLY)/
  UNTIL_PART = /UNTIL=(?<date>\d{8})(?:T(?<time>\d{6}))?(?<utc>Z?)/

  Occurrence = Data.define(:starts_at, :ends_at, :original_start, :all_day, :override)
  Result = Data.define(:occurrences, :truncated)

  # `record` is an Event or StaffUnavailability.
  def self.for_record(record)
    new(rule: record.recurrence_rule, starts_at: record.start_time.in_time_zone(ZONE), ends_at: record.end_time)
  end

  # `starts_at` is a TimeWithZone; the series repeats the wall time of its zone.
  # Exclusions are the rule's own EXDATE lines, read as instants.
  def initialize(rule:, starts_at:, ends_at:)
    @rule = rule
    @zone = starts_at.time_zone
    @starts_at = starts_at
    ends_at = ends_at.in_time_zone(@zone)
    @all_day = CalendarTime.all_day?(@starts_at, ends_at)
    @days = (ends_at.to_date - @starts_at.to_date).to_i
    @seconds = ends_at - @starts_at
    @excluded = RecurrenceExpansion.exdate_instants(rule)
    @first_instant = @zone.local(*@starts_at.to_a[0, 6].reverse)
    # The second of two equal wall times on a fall-back night.
    @second_instant_start = !@starts_at.dst? && @first_instant.to_i != @starts_at.to_i
  end

  # `window` is a Range of instants (CalendarWindow#to_range).
  # Occurrences that start in the window (the /api/v1 and staff app contract).
  def occurrences_starting_in(window, limit:)
    collect(starts_between(window.begin, window.end), limit)
  end

  # Occurrences that overlap the window, including one that began before it.
  def occurrences_overlapping(window, limit:)
    overlapping = starts_between(window.begin - lookback, window.end)
                  .select { |start| ends_at(start) > window.begin && start < window.end }
    collect(overlapping, limit)
  end

  private

  def collect(starts, limit)
    found = starts.first(limit + 1).map { |start| occurrence(start) }
    Result.new(occurrences: found.first(limit), truncated: found.size > limit)
  end

  def occurrence(start)
    Occurrence.new(starts_at: start, ends_at: ends_at(start), original_start: start, all_day: @all_day, override: nil)
  end

  def ends_at(start)
    @all_day ? start.advance(days: @days) : start + @seconds
  end

  # How far before a window an occurrence can start and still overlap it.
  def lookback
    (@all_day ? @days.days : @seconds) + 1.hour
  end

  # The only method that reaches the repeat library. Lazy: the caller's
  # first(limit + 1) stops the walk. The gem takes COUNT from its start, so the
  # series start is the gem's; only a series that starts at the second 01:30 of a
  # fall-back night needs the explicit mapping below, because the gem resolves
  # that wall time to the first instant and would otherwise drop the start.
  def starts_between(from, to)
    gem_rule(to).each(floor_date: @second_instant_start ? nil : from).lazy
            .take_while { |time| time <= to }
            .map { |time| time == gem_start ? @starts_at : time.in_time_zone(@zone) }
            .select { |time| time >= from && !@excluded.include?(time.to_i) }
  end

  # Rules that repeat elapsed time (HOURLY and finer, only in rules stored before
  # validation) run in UTC, so a clock change does not touch them.
  def gem_rule(to)
    zone_name = RecurrenceExpansion.rule_body(@rule).match?(ELAPSED_TIME) ? "UTC" : @zone.tzinfo.name
    RRule::Rule.new(rule_body, dtstart: gem_start, tzid: zone_name, max_year: to.year + 1)
  end

  # The bare rule body, with UNTIL as an instant: a date means the end of that
  # Toronto day, a time without Z is Toronto wall time.
  def rule_body
    RecurrenceExpansion.rule_body(@rule).sub(UNTIL_PART) do
      match = Regexp.last_match
      next "UNTIL=#{match[:date]}T#{match[:time]}Z" if match[:utc] == "Z"

      "UNTIL=#{@zone.parse("#{match[:date]}T#{match[:time] || '235959'}").utc.strftime(RecurrenceRule::STAMP)}"
    end
  end

  def gem_start
    @second_instant_start ? @first_instant : @starts_at
  end
end
