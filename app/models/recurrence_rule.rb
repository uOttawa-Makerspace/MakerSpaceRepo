# frozen_string_literal: true

# The stored repeat rule of a calendar event or staff unavailability: iCalendar
# lines (an optional DTSTART, the RRULE, then any EXDATE lines) with every time
# written as a UTC stamp. The admin calendar and the staff unavailabilities page
# edit a series the same way; each edit returns the new rule text.
class RecurrenceRule
  STAMP = "%Y%m%dT%H%M%SZ"

  # The bare RRULE body, the DTSTART as a UTC time (nil when there is none) and
  # the other lines of a stored rule.
  def self.parse(text)
    lines = RecurrenceExpansion.lines(text)
    rrule = lines.find { |l| l.start_with?("RRULE:") }&.delete_prefix("RRULE:")
    dtstart = lines.find { |l| l.start_with?("DTSTART:") }&.delete_prefix("DTSTART:")
    [rrule, dtstart.presence && Time.parse(dtstart).utc, lines.reject { |l| l.start_with?("RRULE:", "DTSTART:") }]
  end

  # `series_start` stands in for a rule stored without a DTSTART.
  def initialize(text, series_start)
    @text = text
    @series_start = series_start
    @rrule, @dtstart, @other_lines = self.class.parse(text)
  end

  # The series without the occurrence that starts at `start` ("delete this event").
  def without_occurrence(start)
    rewritten(@rrule, "EXDATE:#{start.utc.strftime(STAMP)}")
  end

  # The series ending a day before the occurrence that starts at `start`
  # ("delete this and following events").
  def ending_before(start)
    rewritten("#{@rrule.gsub(/;UNTIL=[^;Z]*Z/, '')};UNTIL=#{(start - 24.hours).utc.strftime(STAMP)}")
  end

  # The series with one more occurrence left out, the rule kept as written
  # ("update this event": the occurrence becomes an event of its own).
  def with_exdate(start)
    return @text if @text.blank? || start.blank?

    "#{@text}\nEXDATE:#{start.utc.strftime(STAMP)}"
  end

  # The rule of a series whose events all move to the time of day of
  # `new_text` ("update all events"). When the repeat itself is unchanged the
  # series keeps its start date and its exclusions; otherwise `new_text` is the
  # new rule.
  def moved_to_time_of(new_text)
    new_rrule, new_dtstart, = self.class.parse(new_text)
    return new_text unless new_rrule == @rrule && @dtstart && new_dtstart

    start = @dtstart.change(hour: new_dtstart.hour, min: new_dtstart.min, sec: new_dtstart.sec)
    (["DTSTART:#{start.strftime(STAMP)}", "RRULE:#{@rrule}"] + @other_lines).join("\n")
  end

  private

  # The rule written again through the rrule gem, with its start first.
  def rewritten(rrule, *extra_lines)
    rule = RRule::Rule.new(rrule, dtstart: @dtstart || @series_start)
    (["DTSTART:#{rule.dtstart.utc.strftime(STAMP)}", "RRULE:#{rule}"] + extra_lines + @other_lines).join("\n")
  end
end
