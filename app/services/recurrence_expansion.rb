# frozen_string_literal: true

require "ice_cube"

# Bounded expansion of a stored iCalendar recurrence rule (D-SP28). Shared by the
# legacy staff calendar and the /api/v1 shifts serializer so that a rule stored
# before validation existed (e.g. FREQ=MINUTELY, 144k occurrences per 100 days)
# can never pin a worker: occurrences are enumerated lazily and stop at `limit`.
module RecurrenceExpansion
  Result = Struct.new(:occurrences, :truncated)

  module_function

  # The bare rule body ("FREQ=DAILY;COUNT=3") of a stored value, which may carry an
  # RRULE: prefix and DTSTART/EXDATE lines.
  def rule_body(rule_string)
    rule_string = rule_string.to_s
    line = lines(rule_string).find { |l| l.start_with?("RRULE:") } ||
           (rule_string.include?("RRULE:") ? rule_string : "RRULE:#{rule_string}")
    line.gsub("RRULE:", "").strip
  end

  # Non-blank lines, each stripped (CRLF and leading whitespace tolerated). The
  # validator, rule_body and the controllers' parser all read lines this way.
  def lines(value)
    value.to_s.lines.map(&:strip).reject(&:empty?)
  end

  # Rules that repeat a wall-clock time (the only ones the validator accepts).
  WALL_CLOCK_RULES = [IceCube::DailyRule, IceCube::WeeklyRule, IceCube::MonthlyRule, IceCube::YearlyRule].freeze

  # Occurrences starting in from..to, at most `limit`. Raises what IceCube raises
  # for a rule it cannot parse.
  #
  # DST (D-SP29), for a wall-clock rule on a zoned start time: IceCube already
  # moves a nonexistent local time forward (02:30 on a spring-forward day becomes
  # 03:30 daylight time), but on a fall-back day it yields a time in the repeated
  # hour twice (01:30 daylight AND 01:30 standard) and counts both against COUNT.
  # Here the second one is dropped, so the time is listed once, at its first
  # (daylight) instant, and COUNT is applied after that by this method. The
  # window is tested against that kept instant only, so a window opening inside
  # the repeated hour after it (e.g. 01:45 daylight) excludes that day's 01:30.
  def occurrences(rule_string, start_time, from, to, limit)
    rule = IceCube::Rule.from_ical(rule_body(rule_string))
    # enumerate_occurrences is private in IceCube but is the only variant taking a
    # closing time; lazy.first(limit + 1) stops enumeration early (the extra one
    # only detects truncation).
    found = if wall_clock?(rule, start_time)
              wall_clock_occurrences(rule, start_time, from, to)
            else
              enumerate(rule, start_time, from, to)
            end.first(limit + 1)
    Result.new(found.first(limit), found.size > limit)
  end

  def wall_clock?(rule, start_time)
    WALL_CLOCK_RULES.any? { |klass| rule.is_a?(klass) } && start_time.respond_to?(:time_zone)
  end

  # Lazy occurrences of a wall-clock rule, the repeated-hour duplicates removed.
  # With a COUNT, enumeration starts at the series start (as IceCube itself does
  # for COUNT) so the count is taken over the de-duplicated series. Everything
  # stays lazy: the caller's first(limit + 1) stops the walk inside the window.
  def wall_clock_occurrences(rule, start_time, from, to)
    count = rule.occurrence_count
    # A copy without the COUNT: the parsed rule itself is left untouched.
    rule = IceCube::Rule.from_hash(rule.to_hash.except(:count)) if count
    times = enumerate(rule, start_time, count ? start_time : from, to)
            .reject { |time| repeated_hour_duplicate?(time, start_time) }
    times = times.take(count) if count
    times.select { |time| time >= from }
  end

  # True for the second (standard-time) instant of a local time that occurs twice,
  # unless it is the series start itself. TimeZone#local resolves an ambiguous
  # local time to its first (daylight) instant. A daylight-time instant is never
  # the second one, so it skips the lookup.
  def repeated_hour_duplicate?(time, start_time)
    return false if time.dst? || time == start_time

    first = start_time.time_zone.local(time.year, time.month, time.day, time.hour, time.min, time.sec)
    first.to_i != time.to_i
  end

  def enumerate(rule, start_time, from, to)
    schedule = IceCube::Schedule.new(start_time)
    schedule.add_recurrence_rule(rule)
    schedule.send(:enumerate_occurrences, from, to).lazy
  end
end
