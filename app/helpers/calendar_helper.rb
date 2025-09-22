module CalendarHelper
  def parse_ics_calendar(ics_url, name: "Unnamed Calendar", color: nil)
    return [] if ics_url.blank?

    background_color = color.presence || generate_color_from_id(ics_url)
    group_id = Digest::MD5.hexdigest(ics_url)

    events = []

    begin
      response = HTTParty.get(ics_url, timeout: 10)
      return [] unless response.success?

      parsed_cals = ::Icalendar::Calendar.parse(response.body)

      events = parsed_cals.flat_map do |calendar|
        calendar.events.map do |event|
          next if event.rrule.empty? && event.dtend < (Time.now.utc - 2.months)

          event_hash = {
            id: event.uid,
            groupId: group_id,
            title: event.summary,
            extendedProps: {
              name: name,
              description: event.description,
              location: event.location,
            },
            allDay: event.dtstart.to_time == event.dtend.to_time - 1.day,
            start: event.dtstart.to_time.iso8601
          }

          if event.rrule.any?
            dtstart = begin
              event.dtstart.to_time
            rescue StandardError
              event.dtstart
            end

            event_hash[:start] = dtstart.iso8601
            event_hash[:rrule] = open_struct_to_rrule(event.rrule.first.value, dtstart)

            if event.dtend && event.dtstart
              duration_seconds = event.dtend.to_time - event.dtstart.to_time
              event_hash[:duration] = duration_seconds * 1000
            end
          elsif event.dtend
            event_hash[:end] = event.dtend.to_time.iso8601
          end

          event_hash
        end.compact
      end
    rescue StandardError => e
      Rails.logger.error("ICS parse error for #{ics_url}: #{e.message}")
    end

    [{ id: group_id, color: background_color, events: events }]
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
  def open_struct_to_rrule(recur, dtstart)
    rule = case recur.frequency&.downcase
      when "daily" then IceCube::Rule.daily
      when "weekly" then IceCube::Rule.weekly
      when "monthly" then IceCube::Rule.monthly
      when "yearly" then IceCube::Rule.yearly
      else
        raise ArgumentError, "Unsupported frequency: #{recur.frequency}"
      end

    rule.interval(recur.interval) if recur.interval
    rule.count(recur.count) if recur.count
    rule.until(Time.parse(recur.until).utc) if recur.until

    if recur.by_day
      days = recur.by_day.map do |day|
        {
          "SU" => :sunday,
          "MO" => :monday,
          "TU" => :tuesday,
          "WE" => :wednesday,
          "TH" => :thursday,
          "FR" => :friday,
          "SA" => :saturday
        }[day]
      end.compact
      rule.day(*days)
    end

    # Create a temporary schedule just to extract the RRULE string
    schedule = IceCube::Schedule.new(dtstart)
    schedule.add_recurrence_rule(rule)

    
    "DTSTART:#{schedule.start_time.utc.strftime('%Y%m%dT%H%M%SZ')}\n" + "RRULE:#{schedule.rrules.first.to_ical}"
  end 
  
  def parse_rrule_and_dtstart(rule_string)
    lines = rule_string.strip.split("\n")
    rrule_line = lines.find { |l| l.start_with?("RRULE:") }&.sub("RRULE:", "")
    dtstart_line = lines.find { |l| l.start_with?("DTSTART:") }&.sub("DTSTART:", "")

    rest_of_lines = lines.reject { |l| l.start_with?("RRULE:", "DTSTART:") }

    dtstart = dtstart_line.present? ? Time.parse(dtstart_line).utc : nil
    
    [rrule_line, dtstart, rest_of_lines]
  end

  def add_exdate_to_rrule(rrule_str, date_to_exclude)
    return rrule_str if rrule_str.blank? || date_to_exclude.blank?

    exdate = date_to_exclude.strftime('%Y%m%dT%H%M%SZ')
    "#{rrule_str}\nEXDATE:#{exdate}"
  end

  def combine_date_and_time(keep_date, keep_time)
    keep_date.change(
      hour: keep_time.hour,
      min: keep_time.min,
      sec: keep_time.sec
    )
  end

  def remove_until_from_rrule(rrule_line)
    rrule_line = rrule_line.gsub(/;UNTIL=[^;Z]*Z/, '') if rrule_line.include?('UNTIL=')
    rrule_line
  end

  def create_makeroom_bookings_from_ics(snc)
    # Filter all CEED Space events into the ones for STEM124 and the ones for STEM126

    @events = parse_ics_calendar(
        snc.calendar_url,
        name: snc.name.presence || "Unnamed Calendar",
        color: snc.color
      )
    # Arrays for each rooms' events
    @events_124 = []
    @events_126 = []
    @events.each do |event|
      Rails.logger.debug event
      Rails.logger.debug "_________________________________________________"
      if event.extendedProps.location == "STEM124"
        @events_124 << event
      elsif event.extendedProps.location == "STEM126"
        @events_126 << event
      end
    end
    
    # Creating the bookings
    @events_124.each do |event|
      create SubSpaceBooking(
        start_time: event.start,
        end_time: event.end,
        name: event.name,
        description: event.description,
        sub_space_id: 10,
        blocking: true
      )
    end

    # Creating the bookings
    @events_126.each do |event|
      create SubSpaceBooking(
        start_time: event.start,
        end_time: event.end,
        name: event.name,
        description: event.description,
        sub_space_id: 11,
        blocking: true
      )
    end
  end
end
