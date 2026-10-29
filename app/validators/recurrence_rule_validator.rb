# frozen_string_literal: true

require "ice_cube"

# D-SP28: a recurrence_rule is blank or an RRULE whose FREQ is DAILY, WEEKLY,
# MONTHLY or YEARLY. Sub-daily rules (SECONDLY/MINUTELY/HOURLY) are refused
# because the calendars expand them on every load.
#
# Accepts what the forms produce (rrule.js toString: an optional
# "DTSTART:...\n" line, then "RRULE:FREQ=...;BYDAY=..;UNTIL=..;COUNT=..", plus
# EXDATE lines added by the occurrence editors) and a bare "FREQ=..." body.
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

  # nil when valid, else the message.
  def self.error_for(value)
    bodies = rule_bodies(value.to_s)
    return UNPARSEABLE if bodies.empty?

    bodies.each do |body|
      freq = body[/(?:\A|;)\s*FREQ=([A-Za-z]+)/i, 1]&.upcase
      return UNPARSEABLE if freq.nil?
      return MESSAGE unless ALLOWED_FREQUENCIES.include?(freq)

      begin
        IceCube::Rule.from_ical(body)
      rescue StandardError
        return UNPARSEABLE
      end
    end
    nil
  end

  def self.rule_bodies(value)
    lines = value.lines.map(&:strip).reject(&:empty?)
    prefixed = lines.select { |l| l.start_with?("RRULE:") }
    return prefixed.map { |l| l.delete_prefix("RRULE:").strip } if prefixed.any?

    # No RRULE: prefix: the bare body (what the existing readers assume), ignoring
    # DTSTART/EXDATE-style property lines.
    lines.reject { |l| l.match?(/\A(DTSTART|EXDATE|RDATE|EXRULE)[:;]/i) }.first(1)
  end
end
