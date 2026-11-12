# frozen_string_literal: true

# Bounded expansion of a stored iCalendar recurrence rule. Shared by the
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

  # Occurrences starting in from..to, at most `limit`, as start times; the work
  # is RecurringSeries'. Raises what the repeat library raises for a rule it
  # cannot parse.
  def occurrences(rule_string, start_time, from, to, limit)
    found = RecurringSeries.new(rule: rule_string, starts_at: start_time.in_time_zone(start_time.try(:time_zone) || RecurrenceRule::ZONE), ends_at: start_time)
                           .occurrences_starting_in(from..to, limit: limit)
    Result.new(found.occurrences.map(&:starts_at), found.truncated)
  end

  # Epoch seconds of every EXDATE value in a stored rule (a line may list
  # several, comma separated). A stamp ending in Z is an instant; one without
  # is wall-clock time in the line's TZID, or in Toronto when it names none
  # (as the calendar views read it). A plain date (VALUE=DATE) is that day's
  # midnight in the zone. Any other value is skipped.
  def exdate_instants(rule_string)
    lines(rule_string).select { |l| l.start_with?("EXDATE") }.flat_map do |line|
      params, values = line.delete_prefix("EXDATE").split(":", 2)
      zone = ActiveSupport::TimeZone[params.to_s[/TZID=([^;:]+)/, 1] || RecurrenceRule::ZONE.name] || RecurrenceRule::ZONE
      values.to_s.split(",").filter_map { |value| exdate_instant(value.strip, zone) }
    end.to_set
  end

  def exdate_instant(value, zone)
    return unless value.match?(/\A\d{8}(T\d{6}Z?)?\z/)

    (value.end_with?("Z") ? Time.zone.parse(value) : zone.parse(value)).to_i
  end
end
