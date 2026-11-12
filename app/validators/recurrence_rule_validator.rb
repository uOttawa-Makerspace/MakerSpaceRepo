# frozen_string_literal: true

# a recurrence_rule is blank or an RRULE whose FREQ is DAILY, WEEKLY,
# MONTHLY or YEARLY. Sub-daily rules (SECONDLY/MINUTELY/HOURLY) are refused
# because the calendars expand them on every load.
#
# Requires the "RRULE:" line format the forms produce: an optional start line,
# either "DTSTART;TZID=America/Toronto:<wall time>" (what the calendars write)
# or "DTSTART:<UTC stamp>Z" (older rules), then
# "RRULE:FREQ=...;BYDAY=..;UNTIL=..;COUNT=..", plus EXDATE lines added by the
# occurrence editors. The RRULE and DTSTART lines are checked (a DTSTART must be
# readable by RecurrenceRule); EXDATE lines are not. A bare "FREQ=..." is
# rejected because the calendar's series edits (RecurrenceRule) cannot read it.
# BYHOUR/BYMINUTE/BYSECOND/BYSETPOS are rejected (they multiply daily occurrences).
#
#   validates :recurrence_rule, recurrence_rule: true
class RecurrenceRuleValidator < ActiveModel::EachValidator
  ALLOWED_FREQUENCIES = %w[DAILY WEEKLY MONTHLY YEARLY].freeze
  MESSAGE = "must repeat daily, weekly, monthly or yearly (repeating more often than daily is not allowed)"
  UNPARSEABLE = "is not a valid repeat rule"

  def validate_each(record, attribute, value)
    return if value.blank?

    error = self.class.error_for(value)
    record.errors.add(attribute, error) if error
  end

  MAX_LENGTH = 2000
  TOO_LONG = "is too long (maximum is #{MAX_LENGTH} characters)"
  # Part => the message for a rule that has it. BYWEEKNO is something stored rules have
  # never allowed; the others multiply daily occurrences.
  PART_ERRORS = { "BYWEEKNO" => UNPARSEABLE, "BYHOUR" => MESSAGE, "BYMINUTE" => MESSAGE,
                  "BYSECOND" => MESSAGE, "BYSETPOS" => MESSAGE }.freeze
  # FREQ => the message for it, or nil when allowed; any other FREQ is unparseable.
  FREQUENCIES = { "DAILY" => nil, "WEEKLY" => nil, "MONTHLY" => nil, "YEARLY" => nil,
                  "SECONDLY" => MESSAGE, "MINUTELY" => MESSAGE, "HOURLY" => MESSAGE }.freeze
  # The repeat library accepts these parts without checking their numbers.
  NUMBER_RANGES = { "BYMONTH" => 1..12, "BYMONTHDAY" => 1..31, "BYYEARDAY" => 1..366 }.freeze

  # nil when valid, else the message.
  def self.error_for(value)
    value = value.to_s
    return TOO_LONG if value.length > MAX_LENGTH

    bodies = rule_bodies(value)
    return UNPARSEABLE if bodies.empty? || !readable_starts?(value)

    bodies.filter_map { |body| body_error(body) }.first
  end

  # nil when one RRULE body is allowed, else the message.
  def self.body_error(body)
    parts = body.split(";").map { |part| part.split("=", 2).map(&:strip).then { |k, v| [k.to_s.upcase, v.to_s] } }
    return UNPARSEABLE unless parts.count { |key, _| key == "FREQ" } == 1

    parts.filter_map { |key, _| PART_ERRORS[key] }.first || value_error(parts.to_h, body)
  end

  # The message for the frequency or a number the repeat library would take without checking, else nil.
  def self.value_error(values, body)
    FREQUENCIES.fetch(values["FREQ"], UNPARSEABLE) || (UNPARSEABLE unless numbers_in_range?(values) && readable?(body))
  end

  # Every part with an allowed range has only numbers inside it.
  def self.numbers_in_range?(values)
    NUMBER_RANGES.all? do |key, range|
      values[key].to_s.split(",").all? { |n| range.cover?(Integer(n, 10, exception: false).to_i.abs) }
    end
  end

  def self.readable?(body)
    RRule::Rule.new(body, dtstart: Time.utc(2000), tzid: "UTC")
    true
  rescue RRule::InvalidRRule, ArgumentError, NoMethodError
    # The gem raises InvalidRRule for COUNT and INTERVAL, ArgumentError for a date it cannot read. Anything else is a bug and is not hidden.
    false
  end

  # Every DTSTART line must be a start the series edits (RecurrenceRule) can read.
  def self.readable_starts?(value)
    RecurrenceRule.lines(value).select { |l| l.start_with?("DTSTART") }.all? { |l| RecurrenceRule.readable_start?(l) }
  end

  # The RRULE: lines (what the forms produce), stripped like the controllers' parser.
  # A value with no RRULE: line yields no bodies, so it is rejected.
  def self.rule_bodies(value)
    RecurrenceRule.lines(value).select { |l| l.start_with?("RRULE:") }
                       .map { |l| l.delete_prefix("RRULE:").strip }
  end
end
