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
  FORBIDDEN_PARTS = %w[BYHOUR BYMINUTE BYSECOND BYSETPOS].freeze
  # The repeat library accepts these parts without checking their numbers or, for
  # BYWEEKNO, stored rules have never allowed them.
  UNSUPPORTED_PARTS = %w[BYWEEKNO].freeze
  NUMBER_RANGES = { "BYMONTH" => 1..12, "BYMONTHDAY" => 1..31, "BYYEARDAY" => 1..366 }.freeze

  # nil when valid, else the message. The frequency is taken from the PARSED rule
  # (its last FREQ), never from a regex over the text.
  def self.error_for(value)
    value = value.to_s
    return TOO_LONG if value.length > MAX_LENGTH

    bodies = rule_bodies(value)
    return UNPARSEABLE if bodies.empty? || !readable_starts?(value)

    bodies.each do |body|
      error = body_error(body)
      return error if error
    end
    nil
  end

  # nil when one RRULE body is allowed, else the message.
  def self.body_error(body)
    keys = body.split(";").map { |part| part.split("=", 2).first.to_s.strip.upcase }
    return UNPARSEABLE unless keys.include?("FREQ")
    return UNPARSEABLE if keys.count("FREQ") > 1 || keys.intersect?(UNSUPPORTED_PARTS)
    return MESSAGE if keys.intersect?(FORBIDDEN_PARTS)

    frequency_error(body)
  end

  def self.frequency_error(body)
    parts = body.split(";").to_h { |part| part.split("=", 2).map(&:strip) }
    return UNPARSEABLE unless parts["FREQ"].to_s.match?(/\A[A-Z]+\z/)
    return MESSAGE unless ALLOWED_FREQUENCIES.include?(parts["FREQ"])

    UNPARSEABLE unless numbers_in_range?(parts) && readable?(body)
  end

  def self.numbers_in_range?(parts)
    NUMBER_RANGES.all? do |key, range|
      parts[key].to_s.split(",").all? { |n| n.match?(/\A-?\d+\z/) && range.cover?(n.to_i.abs) }
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
    RecurrenceExpansion.lines(value).select { |l| l.start_with?("DTSTART") }.all? { |l| RecurrenceRule.readable_start?(l) }
  end

  # The RRULE: lines (what the forms produce), stripped like the controllers' parser.
  # A value with no RRULE: line yields no bodies, so it is rejected.
  def self.rule_bodies(value)
    RecurrenceExpansion.lines(value).select { |l| l.start_with?("RRULE:") }
                       .map { |l| l.delete_prefix("RRULE:").strip }
  end
end
