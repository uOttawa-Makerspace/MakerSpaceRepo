# frozen_string_literal: true

# The stored repeat rule of a calendar event or staff unavailability: iCalendar
# lines (an optional DTSTART, the RRULE, then any EXDATE lines). The start is
# either a UTC stamp (DTSTART:20270310T150000Z) or a Toronto wall-clock time
# (DTSTART;TZID=America/Toronto:20270310T100000); both are read the same way,
# and edits write the Toronto form. UNTIL and EXDATE are UTC stamps. The admin
# calendar and the staff unavailabilities page edit a series the same way;
# each edit returns the new rule text.
class RecurrenceRule
  STAMP = "%Y%m%dT%H%M%SZ"
  WALL_STAMP = "%Y%m%dT%H%M%S"
  ZONE = ActiveSupport::TimeZone["America/Toronto"]

  # The instant of a DTSTART line: a stamp ending in Z is UTC; one without is
  # wall-clock time in its TZID, or in Toronto when it names none. Nil when the
  # line has no stamp; raises ArgumentError for a stamp or zone that cannot be read.
  def self.start_of(line)
    params, stamp = line.delete_prefix("DTSTART").split(":", 2)
    return if stamp.blank?
    return Time.parse(stamp) if stamp.end_with?("Z")

    zone_name = params.delete_prefix(";TZID=").presence || ZONE.name
    zone = ActiveSupport::TimeZone[zone_name] or raise ArgumentError, "unknown time zone #{zone_name}"
    zone.parse(stamp)
  end

  # `series_start` stands in for a rule stored without a DTSTART.
  def initialize(text, series_start)
    @text = text
    @series_start = series_start
    @rrule, @dtstart, @other_lines = parts(text)
  end

  # The rule as the calendar views read it (rrule.js has no time zones): the
  # series start, then the other lines with every UTC stamp (UNTIL, EXDATE)
  # in Toronto wall-clock time, so a series ends on its last Toronto day.
  def in_toronto_time
    lines = RecurrenceExpansion.lines(@text).reject { |l| l.start_with?("DTSTART") }
    (["DTSTART:#{wall_stamp(@series_start)}"] + lines.map { |l| in_wall_time(l) }).join("\n")
  end

  # The series without the occurrence that starts at `start` ("delete this
  # event"), written again through the rrule gem.
  def without_occurrence(start)
    rewritten(@rrule, "EXDATE:#{start.utc.strftime(STAMP)}")
  end

  # The series ending a day before the occurrence that starts at `start`
  # ("delete this and following events").
  def ending_before(start)
    rewritten("#{@rrule.gsub(/;UNTIL=[^;Z]*Z/, '')};UNTIL=#{(start - 24.hours).utc.strftime(STAMP)}")
  end

  # The rule as written with one EXDATE line appended, not rewritten through
  # the gem ("update this event": the occurrence becomes an event of its own).
  def appending_exdate(start)
    return @text if @text.blank? || start.blank?

    "#{@text}\nEXDATE:#{start.utc.strftime(STAMP)}"
  end

  # The series with the Toronto clock time of the DTSTART in `new_text`
  # ("update all events"). When the repeat itself is unchanged the series keeps its start
  # date and its exclusions; otherwise `new_text` is the new rule.
  def with_time_from(new_text)
    new_rrule, new_dtstart, = parts(new_text)
    return new_text unless new_rrule == @rrule && @dtstart && new_dtstart

    new_time = new_dtstart.in_time_zone(ZONE)
    start = @dtstart.in_time_zone(ZONE).change(hour: new_time.hour, min: new_time.min, sec: new_time.sec)
    ([start_line(start), "RRULE:#{@rrule}"] + @other_lines).join("\n")
  end

  private

  # The bare RRULE body, the DTSTART as a UTC time (nil when there is none) and
  # the other lines of a stored rule.
  def parts(text)
    lines = RecurrenceExpansion.lines(text)
    rrule = lines.find { |l| l.start_with?("RRULE:") }&.delete_prefix("RRULE:")
    dtstart = lines.find { |l| l.start_with?("DTSTART") }
    [rrule, dtstart && self.class.start_of(dtstart)&.utc, lines.reject { |l| l.start_with?("RRULE:", "DTSTART") }]
  end

  # The start as it is written: Toronto wall-clock time, so the series keeps
  # its clock time across clock changes.
  def start_line(time)
    "DTSTART;TZID=#{ZONE.tzinfo.name}:#{wall_stamp(time)}"
  end

  def wall_stamp(time)
    time.in_time_zone(ZONE).strftime(WALL_STAMP)
  end

  # The line with each UTC stamp in it written as Toronto wall-clock time.
  def in_wall_time(line)
    line.gsub(/\d{8}T\d{6}Z/) { |stamp| wall_stamp(Time.parse(stamp)) }
  end

  # The rule written again through the rrule gem, with its start first.
  def rewritten(rrule, *extra_lines)
    rule = RRule::Rule.new(rrule, dtstart: @dtstart || @series_start)
    ([start_line(rule.dtstart), "RRULE:#{rule}"] + extra_lines + @other_lines).join("\n")
  end
end
