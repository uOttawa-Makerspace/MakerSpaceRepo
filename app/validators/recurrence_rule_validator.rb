# frozen_string_literal: true

# A recurrence_rule is blank or one RRULE whose FREQ is DAILY, WEEKLY, MONTHLY or YEARLY (sub-daily rules are
# refused: calendars expand them on every load), with known upper-case parts, none twice, and an occurrence soon
# after the start. BYHOUR/BYMINUTE/BYSECOND/BYSETPOS are refused (they multiply daily occurrences).
#
# Requires the "RRULE:" line format the forms produce: an optional start line, either
# "DTSTART;TZID=America/Toronto:<wall time>" or "DTSTART:<UTC stamp>Z" (older rules), then
# "RRULE:FREQ=...;BYDAY=..;UNTIL=..;COUNT=..", plus EXDATE lines added by the occurrence editors. The RRULE and
# DTSTART lines are checked (a DTSTART must be readable by RecurrenceRule); EXDATE lines are not. A bare "FREQ=.."
# is refused because the series edits (RecurrenceRule) cannot read it.
#
#   validates :recurrence_rule, recurrence_rule: true
class RecurrenceRuleValidator < ActiveModel::EachValidator
  ALLOWED_FREQUENCIES = %w[DAILY WEEKLY MONTHLY YEARLY].freeze
  MESSAGE = "must repeat daily, weekly, monthly or yearly (repeating more often than daily is not allowed)"
  UNPARSEABLE = "is not a valid repeat rule"

  def validate_each(record, attribute, value)
    return if value.blank?

    error = self.class.error_for(value, record.try(:start_time) || DEFAULT_START)
    record.errors.add(attribute, error) if error
  end

  DEFAULT_START = RecurrenceRule::ZONE.local(2000, 1, 3, 9) # when the record has no start
  HORIZON_YEARS = 40 # per INTERVAL: the longest gap between leap days on one weekday (2100 is not a leap year)
  MAX_LENGTH = 2000
  TOO_LONG = "is too long (maximum is #{MAX_LENGTH} characters)"
  # Part => the message for a rule that has it (BYWEEKNO was never allowed; the others multiply daily occurrences).
  PART_ERRORS = { "BYWEEKNO" => UNPARSEABLE, "BYHOUR" => MESSAGE, "BYMINUTE" => MESSAGE,
                  "BYSECOND" => MESSAGE, "BYSETPOS" => MESSAGE }.freeze
  # FREQ => the message for it, or nil when allowed; any other FREQ is unparseable.
  FREQUENCIES = { "DAILY" => nil, "WEEKLY" => nil, "MONTHLY" => nil, "YEARLY" => nil,
                  "SECONDLY" => MESSAGE, "MINUTELY" => MESSAGE, "HOURLY" => MESSAGE }.freeze
  # Part => what its value looks like, for the parts the repeat library would take without checking.
  WEEKDAY = "(?:MO|TU|WE|TH|FR|SA|SU)"
  LIST = ->(item) { /\A#{item}(?:,#{item})*\z/ }
  VALUE_FORMATS = {
    "WKST" => /\A#{WEEKDAY}\z/,
    "BYMONTH" => LIST.call("(?:[1-9]|1[0-2])"),
    "BYMONTHDAY" => LIST.call("[+-]?(?:[1-9]|[12]\\d|3[01])"),
    "BYYEARDAY" => LIST.call("[+-]?(?:[1-9]\\d?|[12]\\d\\d|3[0-5]\\d|36[0-6])")
  }.freeze
  # BYDAY by FREQ (RFC 5545): no ordinal for daily and weekly, 1 to 5 for monthly (and yearly with BYMONTH), 1 to 53 for
  # yearly. The repeat library raises on an ordinal the frequency cannot have.
  BYDAY_FORMATS = {
    "DAILY" => WEEKDAY, "WEEKLY" => WEEKDAY, "MONTHLY" => "(?:[+-]?[1-5])?#{WEEKDAY}",
    "YEARLY" => "(?:[+-]?(?:[1-9]|[1-4]\\d|5[0-3]))?#{WEEKDAY}"
  }.transform_values { |item| LIST.call(item) }.freeze
  # What a rule may contain, by where it comes from. Stored rules have never allowed BYWEEKNO and BYSETPOS (see
  # PART_ERRORS); an imported calendar's rules may have them, with values in range.
  STORED = { part_errors: PART_ERRORS, formats: VALUE_FORMATS }.freeze
  IMPORTED = {
    part_errors: PART_ERRORS.except("BYWEEKNO", "BYSETPOS"),
    formats: VALUE_FORMATS.merge(
      "BYWEEKNO" => LIST.call("[+-]?(?:[1-9]|[1-4]\\d|5[0-3])"),
      "BYSETPOS" => LIST.call("[+-]?(?:[1-9]\\d?|[12]\\d\\d|3[0-5]\\d|36[0-6])")
    )
  }.freeze

  # Rule part names are upper case and known; anything else is not a repeat rule.
  KNOWN_PARTS = (%w[FREQ COUNT UNTIL INTERVAL BYDAY] + PART_ERRORS.keys + VALUE_FORMATS.keys).freeze

  # nil when valid, else the message. `mode` is STORED (the default) or IMPORTED.
  def self.error_for(value, start = DEFAULT_START, mode = STORED)
    value = value.to_s
    return TOO_LONG if value.length > MAX_LENGTH

    bodies = rule_bodies(value)
    return UNPARSEABLE if bodies.empty? || !readable_starts?(value)
    return I18n.t("errors.calendar.rule_one_line") if bodies.size > 1 # a series only ever uses the first

    body_error(bodies.first, start, mode)
  end

  # nil when one RRULE body is allowed, else the message.
  def self.body_error(body, start, mode)
    parts = body.split(";").map { |part| part.split("=", 2).map(&:strip).then { |key, value| [key.to_s, value.to_s] } }
    return UNPARSEABLE unless known_parts?(parts.map(&:first))

    parts.filter_map { |key, _| mode[:part_errors][key] }.first || value_error(parts.to_h, body, start, mode)
  end

  # A FREQ, no part name twice (the last value would hide the first), every name known and in upper case.
  def self.known_parts?(keys)
    keys.include?("FREQ") && keys.uniq == keys && (keys - KNOWN_PARTS).empty?
  end

  # The message for the frequency, a value the library would take unchecked, or a rule with no occurrence, else nil.
  def self.value_error(values, body, start, mode)
    FREQUENCIES.fetch(values["FREQ"], UNPARSEABLE) ||
      (UNPARSEABLE unless formats_ok?(values, mode[:formats]) && readable?(body)) ||
      (I18n.t("errors.calendar.rule_never_repeats") if never_repeats?(values, body, start))
  end

  # No occurrence soon after the start (COUNT and UNTIL end a series; they do not make its pattern empty).
  def self.never_repeats?(values, body, start)
    pattern = body.gsub(/;?(?:COUNT|UNTIL)=[^;]*/i, "")
    start = start.in_time_zone(RecurrenceRule::ZONE)
    series = RecurringSeries.new(rule: pattern, starts_at: start, ends_at: start + 1.hour)
    horizon = start + [HORIZON_YEARS * values["INTERVAL"].to_i.clamp(1, 100), RecurringSeries::MAX_YEARS].min.years
    series.occurrences_starting_in(start..horizon, limit: 1).occurrences.empty?
  end

  def self.formats_ok?(values, formats)
    frequency = values["FREQ"] == "YEARLY" && values.key?("BYMONTH") ? "MONTHLY" : values["FREQ"]
    formats.merge("BYDAY" => BYDAY_FORMATS.fetch(frequency)).all? { |key, format| !values.key?(key) || values[key].match?(format) }
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
