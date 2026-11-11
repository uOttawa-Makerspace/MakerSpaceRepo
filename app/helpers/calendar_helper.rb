module CalendarHelper
  # The values RFC 5545 allows for the BY parts of a repeat rule, and whether the value may be negative.
  ICS_RULE_PART_LIMITS = {
    by_year_day: [1..366, true],
    by_month_day: [1..31, true],
    by_week_number: [1..53, true],
    by_month: [1..12, false],
    by_set_position: [1..366, true]
  }.freeze

  # One BYDAY value: a weekday, optionally with a number (and sign) saying which one of the period.
  ICS_BY_DAY = /\A(?:[+-]?(?<number>\d+))?(?:MO|TU|WE|TH|FR|SA|SU)\z/

  # The longest COUNT whose end is worked out when deciding whether a series is over.
  MAX_COUNTED_SERIES = 1000

  # The feed as one calendar of events, or no calendar at all (an empty list) when the server did not answer with
  # a feed body. A feed that cannot be fetched or read has the error added to failures (when given) and no events.
  def parse_ics_calendar(ics_url, name: "Unnamed Calendar", color: nil, failures: nil)
    return [] if ics_url.blank?

    background_color = color.presence || generate_color_from_id(ics_url.to_s)
    group_id = Digest::MD5.hexdigest(ics_url.to_s)

    events = ics_feed_events(ics_url, group_id, name, failures)
    return [] if events.nil?

    [{ id: group_id, color: background_color, events: events }]
  end

  # The events of the feed, nil when there is no body to read.
  def ics_feed_events(ics_url, group_id, name, failures)
    parsed_cals = read_ics_calendars(ics_url)
    return if parsed_cals.nil?

    parsed_cals.flat_map do |calendar|
      # Group events by UID to handle recurrence-id
      calendar.events.group_by(&:uid).flat_map do |_uid, event_group|
        ics_event_group(event_group, group_id: group_id, name: name)
      end
    end
  rescue StandardError => e
    Rails.logger.error("ICS parse error for #{ics_url}: #{e.inspect}")
    failures&.push(e)
    []
  end

  def read_ics_calendars(ics_url)
    return ::Icalendar::Calendar.parse(File.read(ics_url)) if ics_url.is_a?(Pathname)

    body = IcsFetcher.get(ics_url.to_s, timeout: 10)
    ::Icalendar::Calendar.parse(body) unless body.nil?
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

  # RRULE HELPERS
  def convert_rrule_to_string(rrule_obj)
    parts = []
    
    parts << "FREQ=#{rrule_obj.frequency}" if rrule_obj.frequency
    parts << "INTERVAL=#{rrule_obj.interval}" if rrule_obj.interval && rrule_obj.interval != 1
    parts << "BYDAY=#{rrule_obj.by_day.join(',')}" if rrule_obj.by_day&.any?
    parts << "BYMONTHDAY=#{rrule_obj.by_month_day.join(',')}" if rrule_obj.by_month_day&.any?
    parts << "BYMONTH=#{rrule_obj.by_month.join(',')}" if rrule_obj.by_month&.any?
    parts << "BYYEARDAY=#{rrule_obj.by_year_day.join(',')}" if rrule_obj.by_year_day&.any?
    parts << "BYWEEKNO=#{rrule_obj.by_week_number.join(',')}" if rrule_obj.by_week_number&.any?
    parts << "BYSETPOS=#{rrule_obj.by_set_position.join(',')}" if rrule_obj.by_set_position&.any?
    
    if rrule_obj.until
      until_time = safe_to_time(rrule_obj.until)
      # Toronto wall-clock time, like the DTSTART the feed sends with it
      parts << "UNTIL=#{until_time.in_time_zone(RecurrenceRule::ZONE).strftime('%Y%m%dT%H%M%S')}" if until_time
    end
    
    parts << "COUNT=#{rrule_obj.count}" if rrule_obj.count
    parts << "WKST=#{rrule_obj.week_start}" if rrule_obj.week_start
    
    parts.join(';')
  end
  
  # The repeat rule as the calendar views read it (see RecurrenceRule#in_toronto_time).
  def date_formatted_recurrence_rule(event)
    return if event.recurrence_rule.blank?

    RecurrenceRule.new(event.recurrence_rule, event.start_time).in_toronto_time
  end

  # The date of `keep_date` at the clock time of `keep_time`, both read in
  # Toronto time (a repeating series keeps its Toronto clock time across clock
  # changes and late evenings, which are already the next day in UTC).
  def combine_date_and_time(keep_date, keep_time)
    time = keep_time.in_time_zone(RecurrenceRule::ZONE)
    keep_date.in_time_zone(RecurrenceRule::ZONE).change(hour: time.hour, min: time.min, sec: time.sec)
  end

  # A point in time as UTC. Dates and times without a zone (all-day dates,
  # floating times, a bare UNTIL) are Toronto wall-clock time, whatever zone the
  # server process runs in; values with a Z or a TZID keep their own instant.
  def safe_to_time(value)
    return nil if value.nil?

    wall = wall_clock(value)
    (wall ? toronto_local(wall) : instant(value))&.getutc # nil for text that is not a time
  rescue ArgumentError, RangeError
    nil # not a time
  end

  # The date or zoneless date-time in the value (a date object, a floating
  # time, or the bare YYYYMMDD of a recurrence UNTIL), or nil when the value
  # carries its own zone.
  def wall_clock(value)
    return Date.strptime(value, "%Y%m%d") if value.is_a?(String) && value.match?(/\A\d{8}\z/)

    raw = value.is_a?(Icalendar::Values::DateTime) ? value.value : value
    raw if floating_time?(raw) || calendar_date?(raw)
  end

  # icalendar leaves a plain DateTime with no offset for a time with no zone and
  # for a TZID it cannot resolve (for example a custom name with no VTIMEZONE);
  # both are read as Toronto time. A resolved TZID gives a zoned value, and a
  # plain DateTime with an offset is an instant.
  def floating_time?(raw)
    raw.instance_of?(::DateTime) && raw.offset.zero?
  end

  def calendar_date?(raw)
    raw.is_a?(Icalendar::Values::Date) || (raw.is_a?(::Date) && !raw.is_a?(::DateTime))
  end

  def toronto_local(wall)
    toronto_zone.local(wall.year, wall.month, wall.day, wall.try(:hour).to_i, wall.try(:min).to_i, wall.try(:sec).to_i)
  end

  # Text (a recurrence UNTIL) is read in Toronto; feed values (icalendar dates
  # and date-times) and Ruby times convert themselves. Anything else is not a time.
  def instant(value)
    return toronto_zone.parse(value) if value.is_a?(String)

    value.to_time if value.respond_to?(:to_time)
  end

  def toronto_zone
    ActiveSupport::TimeZone["America/Toronto"]
  end

  def convert_to_js_rrule(openstruct_obj)
    js_rrule = {}
    
    js_rrule[:freq] = openstruct_obj.frequency.downcase if openstruct_obj.frequency
    
    js_rrule[:interval] = openstruct_obj.interval if openstruct_obj.interval
    
    if openstruct_obj.by_day
      js_rrule[:byweekday] = openstruct_obj.by_day.map do |day|
        day.downcase[0..1] # maybe not needed but who knows anymore
      end
    end
    
    js_rrule[:until] = openstruct_obj.until if openstruct_obj.until
    
    js_rrule[:count] = openstruct_obj.count if openstruct_obj.count
    
    %w[by_second by_minute by_hour by_month_day by_year_day 
      by_week_number by_month by_set_position].each do |field|
      value = openstruct_obj.send(field)
      js_rrule[field.to_sym] = value if value
    end
    
    js_rrule[:wkst] = openstruct_obj.week_start if openstruct_obj.week_start
    
    js_rrule
  end

  private

  # The calendar events for one UID: the series (or single event) itself, then each modified instance of it.
  def ics_event_group(event_group, group_id:, name:)
    main_event = event_group.find { |e| e.recurrence_id.nil? }
    modified_instances = event_group.select { |e| e.recurrence_id.present? }

    results = []
    if main_event
      main_hash = ics_main_event(main_event, modified_instances, group_id: group_id, name: name)
      results << main_hash if main_hash
    end
    modified_instances.each do |modified|
      instance_hash = ics_modified_instance(modified, group_id: group_id, name: name)
      results << instance_hash if instance_hash
    end
    results
  end

  # The calendar entry for a single or recurring event, or nil when it ended more than two months ago (a single
  # event) or has no usable start (reported, so the rest of the feed still loads).
  def ics_main_event(main_event, modified_instances, group_id:, name:)
    start_time = safe_to_time(main_event.dtstart)
    end_time = safe_to_time(main_event.dtend)
    return report_ics_event_problem("ICS event has no usable start", main_event, group_id) if start_time.nil?

    rrule_obj = main_event.rrule&.first
    return if skip_ics_event?(main_event, rrule_obj, start_time, end_time, group_id)

    event_hash = {
      id: main_event.uid,
      groupId: group_id,
      title: main_event.summary,
      extendedProps: {
        name: name,
        description: main_event.description,
      },
      allDay: main_event.dtstart.is_a?(Icalendar::Values::Date),
      display: 'auto',
      start: toronto_iso(start_time),
      end: toronto_iso(end_time)
    }
    event_hash.merge!(ics_recurrence(main_event, rrule_obj, modified_instances, start_time, end_time)) if rrule_obj.present?
    event_hash
  end

  def ics_recurrence(main_event, rrule_obj, modified_instances, start_time, end_time)
    rrule_string_parts = []

    dtstart_toronto = start_time.in_time_zone("America/Toronto")&.strftime("%Y%m%dT%H%M%S")
    rrule_string_parts << "DTSTART:#{dtstart_toronto}"

    rrule_line = convert_rrule_to_string(rrule_obj)
    rrule_string_parts << "RRULE:#{rrule_line}"

    ics_exdates(main_event, modified_instances).each do |d|
      exdate_str = d.in_time_zone("America/Toronto")&.strftime("%Y%m%dT%H%M%S")
      rrule_string_parts << "EXDATE:#{exdate_str}"
    end

    recurrence = { rrule: rrule_string_parts.join("\n") }
    recurrence[:duration] = (end_time - start_time).to_i * 1000 if end_time
    recurrence
  end

  # The dates left out of a series: its own exception dates and the original dates of its modified instances.
  def ics_exdates(main_event, modified_instances)
    all_exdates = main_event.exdate.map(&:value).flatten.map { |d| safe_to_time(d) }
    all_exdates += modified_instances.map { |modified| safe_to_time(modified.recurrence_id) }
    all_exdates.compact.uniq
  end

  # A modified instance of a series, listed as an event of its own; nil when it ended more than two months ago.
  def ics_modified_instance(modified, group_id:, name:)
    start_time = safe_to_time(modified.dtstart)
    end_time = safe_to_time(modified.dtend)
    return report_ics_event_problem("ICS event has no usable start", modified, group_id) if start_time.nil?

    return if stale_event?(end_time || start_time)

    {
      id: "#{modified.uid}_#{safe_to_time(modified.recurrence_id)&.to_i}",
      groupId: group_id,
      title: modified.summary,
      extendedProps: {
        name: name,
        description: modified.description,
      },
      allDay: modified.dtstart.is_a?(Icalendar::Values::Date),
      start: toronto_iso(start_time),
      end: toronto_iso(end_time)
    }
  end

  # Whether an event no longer needs showing: a single event that ended, or a series that stopped, more than two
  # months ago.
  # An unreadable series rule is reported and the series kept (the calendar view decides what to do with it).
  def skip_ics_event?(main_event, rrule_obj, start_time, end_time, group_id)
    over = rrule_obj.present? ? series_ended?(rrule_obj, start_time) : stale_event?(end_time || start_time)
    report_ics_event_problem(over, main_event, group_id) if over.is_a?(StandardError)
    over == true
  end

  # Whether a repeating series stopped (by its UNTIL date, or after its COUNT occurrences) more than two months
  # ago. A series that never ends, or whose end cannot be worked out, is not ended.
  def series_ended?(rrule_obj, start_time)
    cutoff = Time.now.utc - 2.months
    until_time = safe_to_time(rrule_obj.until)
    return true if until_time && until_time < cutoff

    counted_series_ended_before?(rrule_obj, start_time, cutoff)
  end

  # Whether all the occurrences of a series with a COUNT fall before the cutoff. A very long count is not worked
  # out: the series is kept. A rule that cannot be read gives the error describing why instead of true or false.
  def counted_series_ended_before?(rrule_obj, start_time, cutoff)
    count = rrule_obj.count.to_i
    return false unless count.between?(1, MAX_COUNTED_SERIES)

    out_of_range = out_of_range_rule_part(rrule_obj)
    return ArgumentError.new("#{out_of_range} is out of range") if out_of_range

    start = start_time.in_time_zone(RecurrenceRule::ZONE)
    found = expand_counted_series(convert_rrule_to_string(rrule_obj), start, cutoff, count)
    found.is_a?(StandardError) ? found : found.occurrences.size == count
  end

  # The occurrences of a rule before the cutoff, or the ArgumentError IceCube raises for a rule it does not support.
  def expand_counted_series(rule_string, start, cutoff, count)
    RecurrenceExpansion.occurrences(rule_string, start, start, cutoff, count)
  rescue ArgumentError => e
    e
  end

  # The first part of the rule whose value is outside what RFC 5545 allows (IceCube fails with a method error on
  # some of these, and accepts others silently), or nil. Only the parts convert_rrule_to_string passes on are
  # checked. A BY part with a sign may count from the end, so only its size is checked.
  def out_of_range_rule_part(rrule_obj)
    return :interval unless rrule_obj.interval.nil? || rrule_obj.interval.to_i >= 1
    return :by_day unless Array(rrule_obj.by_day).all? { |token| valid_by_day?(token) }

    ICS_RULE_PART_LIMITS.find { |part, (limit, signed)| !values_within?(rrule_obj.public_send(part), limit, signed) }&.first
  end

  def values_within?(values, limit, signed)
    Array(values).all? do |value|
      number = Integer(value.to_s, 10, exception: false)
      number && limit.cover?(signed ? number.abs : number)
    end
  end

  def valid_by_day?(token)
    match = ICS_BY_DAY.match(token.to_s)
    match.present? && (match[:number].nil? || match[:number].to_i.between?(1, 53))
  end

  # Whether an event's last moment (its end, else its start) is more than two months ago. An event with
  # no time at all is not stale.
  def stale_event?(last_moment)
    last_moment.present? && last_moment < (Time.now.utc - 2.months)
  end

  def toronto_iso(time)
    time&.in_time_zone("America/Toronto")&.strftime("%Y-%m-%dT%H:%M:%S")
  end

  # Reports an event that cannot be placed on the calendar; returns nil so the caller leaves it out.
  def report_ics_event_problem(problem, event, group_id)
    error = problem.is_a?(StandardError) ? problem : ArgumentError.new(problem)
    Rails.error.report(
      error,
      handled: true, severity: :warning,
      context: { event_uid: event.uid.to_s, calendar: group_id, error_class: error.class.name }
    )
    nil
  end
end
