# frozen_string_literal: true

require "ice_cube"

# D-SP28: a recurrence_rule is blank or an RRULE whose FREQ is DAILY, WEEKLY,
# MONTHLY or YEARLY. Sub-daily rules (SECONDLY/MINUTELY/HOURLY) are refused
# because the calendars expand them on every load.
#
# Requires the "RRULE:" line format the forms produce (rrule.js toString: an
# optional "DTSTART:...\n" line, then "RRULE:FREQ=...;BYDAY=..;UNTIL=..;COUNT=..",
# plus EXDATE lines added by the occurrence editors). A bare "FREQ=..." is
# rejected because the controllers' parse_rrule_and_dtstart cannot read it.
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
  ALLOWED_CLASSES = [IceCube::DailyRule, IceCube::WeeklyRule, IceCube::MonthlyRule, IceCube::YearlyRule].freeze

  # nil when valid, else the message. The frequency is taken from the PARSED rule
  # (IceCube applies the last FREQ), never from a regex over the text.
  def self.error_for(value)
    value = value.to_s
    return TOO_LONG if value.length > MAX_LENGTH

    bodies = rule_bodies(value)
    return UNPARSEABLE if bodies.empty?

    bodies.each do |body|
      keys = body.split(";").map { |part| part.split("=", 2).first.to_s.strip.upcase }
      return UNPARSEABLE unless keys.include?("FREQ")
      return UNPARSEABLE if keys.count("FREQ") > 1
      return MESSAGE if keys.intersect?(FORBIDDEN_PARTS)

      begin
        rule = IceCube::Rule.from_ical(body)
      rescue StandardError
        return UNPARSEABLE
      end
      return MESSAGE unless ALLOWED_CLASSES.include?(rule.class)
    end
    nil
  end

  # The RRULE: lines (what the forms produce), stripped like the controllers' parser.
  # A value with no RRULE: line yields no bodies, so it is rejected.
  def self.rule_bodies(value)
    RecurrenceExpansion.lines(value).select { |l| l.start_with?("RRULE:") }
                       .map { |l| l.delete_prefix("RRULE:").strip }
  end
end
