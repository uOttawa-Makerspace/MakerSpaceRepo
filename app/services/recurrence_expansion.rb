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
    line = rule_string.lines.find { |l| l.start_with?("RRULE:") } ||
           (rule_string.include?("RRULE:") ? rule_string : "RRULE:#{rule_string}")
    line.gsub("RRULE:", "").strip
  end

  # Occurrences starting in from..to, at most `limit`. Raises what IceCube raises
  # for a rule it cannot parse.
  def occurrences(rule_string, start_time, from, to, limit)
    schedule = IceCube::Schedule.new(start_time)
    schedule.add_recurrence_rule(IceCube::Rule.from_ical(rule_body(rule_string)))
    # enumerate_occurrences is private in IceCube but is the only variant taking a
    # closing time; lazy.first(limit + 1) stops enumeration early (the extra one
    # only detects truncation).
    found = schedule.send(:enumerate_occurrences, from, to).lazy.first(limit + 1)
    Result.new(found.first(limit), found.size > limit)
  end
end
