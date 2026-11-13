module CalendarHelper
  # What reading a feed gave: its calendars (one holding the events, or none when the server gave no body) and
  # whether the load failed: no body, a fetch or parse error, or a body with no calendar in it (a web page, say).
  IcsFeed = Struct.new(:calendars, :failed, keyword_init: true) do
    alias_method :failed?, :failed
  end

  # A date-only UNTIL: the series runs through the end of that day.
  ICS_DATE_UNTIL = /UNTIL=(\d{8})(?![\dT])/

  # The calendars of a feed (see ics_feed), without the failure flag.
  def parse_ics_calendar(ics_url, name: "Unnamed Calendar", color: nil, window: CalendarWindow::ALL)
    ics_feed(ics_url, name: name, color: color, window: window).calendars
  end

  # The rows the calendar pages draw for an imported calendar's entries in the window, repeating ones as a rule text.
  def ics_feed(ics_url, name: "Unnamed Calendar", color: nil, window: CalendarWindow::ALL)
    return IcsFeed.new(calendars: [], failed: false) if ics_url.blank?

    calendar = ImportedCalendar.load(ics_url.to_s, name: name, color: color.presence || generate_color_from_id(ics_url.to_s))
    rows = window.entries(calendar.entries).map { |entry| ics_row(entry, calendar) }
    IcsFeed.new(calendars: calendar.fetched? ? [{ id: calendar.id, color: calendar.color, events: rows }] : [], failed: calendar.failed?)
  end

  # COLOR HELPERS
  def generate_color_from_id(id, opacity = 1.0)
    hash = if id.to_i.zero?
      id.to_s.match?(/^\d+$/) ? id.to_i : id.to_s.each_byte.reduce(0) { |sum, b| sum * 31 + b }
    else
      id.to_i
    end

    h = (hash * 137.5) % 360
    s = 80 + (hash % 15)
    l = 50 + (hash % 10)

    # Convert HSL to RGB
    c = (1 - (2 * l / 100.0 - 1).abs) * s / 100.0
    x = c * (1 - ((h / 60.0) % 2 - 1).abs)
    m = l / 100.0 - c / 2.0
    r, g, b = [ [c,x,0], [x,c,0], [0,c,x], [0,x,c], [x,0,c], [c,0,x] ][(h / 60).to_i % 6]
    r = ((r + m) * 255).round
    g = ((g + m) * 255).round
    b = ((b + m) * 255).round

    # Calculate contrast ratio with white
    contrast_ratio = contrast_with_white(r, g, b)

    while contrast_ratio < 3 && l > 18
      l -= 5
      c = (1 - (2 * l / 100.0 - 1).abs) * s / 100.0
      x = c * (1 - ((h / 60.0) % 2 - 1).abs)
      m = l / 100.0 - c / 2.0
      r, g, b = [ [c,x,0], [x,c,0], [0,c,x], [0,x,c], [x,0,c], [c,0,x] ][(h / 60).to_i % 6]
      r = ((r + m) * 255).round
      g = ((g + m) * 255).round
      b = ((b + m) * 255).round
      contrast_ratio = contrast_with_white(r, g, b)
    end

    "rgba(#{r}, #{g}, #{b}, #{opacity})"
  end

  def contrast_with_white(r, g, b)
    # Relative luminance of the color
    rgb = [r, g, b].map do |c|
      c /= 255.0
      c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
    end
    l1 = 1.0 # luminance of white
    l2 = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2] # luminance of the color

    (l1 + 0.05) / (l2 + 0.05)
  end

  # The repeat rule as the calendar views read it (see RecurrenceRule#in_toronto_time).
  def date_formatted_recurrence_rule(event)
    return if event.recurrence_rule.blank?

    RecurrenceRule.new(event.recurrence_rule, event.start_time).in_toronto_time
  end

  private

  def ics_row(entry, calendar)
    row = {
      id: entry.key, groupId: calendar.id, title: entry.summary,
      extendedProps: { name: calendar.name, description: entry.description },
      allDay: entry.all_day, display: "auto", start: toronto_iso(entry.starts_at), end: toronto_iso(entry.ends_at)
    }
    row.merge!(ics_recurrence(entry)) if entry.series
    row
  end

  # The rule as the browser reads it: Toronto wall time throughout, a date UNTIL through the end of its day.
  def ics_recurrence(entry)
    text = RecurrenceRule.new(entry.series.rule, entry.starts_at).in_toronto_time.sub(ICS_DATE_UNTIL, 'UNTIL=\\1T235959')
    recurrence = { rrule: text }
    recurrence[:duration] = (entry.ends_at - entry.starts_at).to_i * 1000 if entry.ends_at > entry.starts_at
    recurrence
  end

  def toronto_iso(time)
    time.in_time_zone(RecurrenceRule::ZONE).strftime("%Y-%m-%dT%H:%M:%S")
  end
end
