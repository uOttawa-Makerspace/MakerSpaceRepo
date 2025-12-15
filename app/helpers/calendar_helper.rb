module CalendarHelper
  def parse_ics_calendar(ics_url, name: "Unnamed Calendar", color: nil )
    return [] if ics_url.blank?

    background_color = color.presence || generate_color_from_id(ics_url)
    group_id = Digest::MD5.hexdigest(ics_url)

    events = []

    begin
      response = HTTParty.get(ics_url, timeout: 10)
      return [] unless response.success?

      parsed_cals = ::Icalendar::Calendar.parse(response.body)

      events = parsed_cals.flat_map do |calendar|
        # Group events by UID to handle recurrence-id
        events_by_uid = calendar.events.group_by(&:uid)
        
        events_by_uid.flat_map do |uid, event_group|
          main_event = event_group.find { |e| e.recurrence_id.nil? }
          modified_instances = event_group.select { |e| e.recurrence_id.present? }
          
          results = []
          
          if main_event
            start_time = safe_to_time(main_event.dtstart)
            end_time = safe_to_time(main_event.dtend)
            all_day = main_event.dtstart.is_a?(Icalendar::Values::Date)

            next if main_event.rrule.empty? && end_time < (Time.now.utc - 2.months)

            event_hash = {
              id: main_event.uid,
              groupId: group_id,
              title: main_event.summary,
              extendedProps: {
                name: name,
                description: main_event.description,
              },
              allDay: all_day,
              display: 'auto',
              start: start_time&.in_time_zone("America/Toronto")&.strftime("%Y-%m-%dT%H:%M:%S"),
              end: end_time&.in_time_zone("America/Toronto")&.strftime("%Y-%m-%dT%H:%M:%S")
            }

            rrule_obj = main_event.rrule&.first

            if rrule_obj.present?
              event_hash[:rrule] = convert_to_js_rrule(rrule_obj)
              event_hash[:rrule][:dtstart] = start_time.in_time_zone("America/Toronto")&.strftime("%Y-%m-%dT%H:%M:%S")
            
              duration_seconds = end_time.to_i - start_time.to_i
              event_hash[:duration] = duration_seconds * 1000
            
              all_exdates = main_event.exdate.map(&:value).flatten.map { |d| safe_to_time(d) }
              
              # Add recurrence-id dates from modified instances to exdates
              modified_instances.each do |modified|
                recurrence_time = safe_to_time(modified.recurrence_id)
                all_exdates << recurrence_time if recurrence_time
              end
              
              exs = all_exdates.map do |d|
 
                                            d.in_time_zone("America/Toronto")&.strftime("%Y-%m-%dT%H:%M:%S")
                                          rescue StandardError
                                            nil
                                           end.compact.uniq
              event_hash[:exdate] = exs if exs.any?
            end
            
            results << event_hash
          end
          
          # Process modified instances as separate events
          modified_instances.each do |modified|
            start_time = safe_to_time(modified.dtstart)
            end_time = safe_to_time(modified.dtend)
            
            next if end_time < (Time.now.utc - 2.months)
            
            results << {
              id: "#{modified.uid}_#{safe_to_time(modified.recurrence_id)&.to_i}",
              groupId: group_id,
              title: modified.summary,
              extendedProps: {
                name: name,
                description: modified.description,
              },
              allDay: modified.dtstart.is_a?(Icalendar::Values::Date),
              start: start_time&.in_time_zone("America/Toronto")&.strftime("%Y-%m-%dT%H:%M:%S"),
              end: end_time&.in_time_zone("America/Toronto")&.strftime("%Y-%m-%dT%H:%M:%S")
            }
          end
          
          results
        end.compact
      end
    rescue StandardError => e
      Rails.logger.error("ICS parse error for #{ics_url}: #{e.inspect}")
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
  def date_formatted_recurrence_rule(event)
    return unless event.recurrence_rule.present?
    
    rrule = event.recurrence_rule
    rrule_parts = rrule.split(/[;\n]/).reject { |part| part.strip.start_with?('DTSTART') }
    rrule_without_dtstart = rrule_parts.join(';').gsub(/;EXDATE/, "\nEXDATE")
    dtstart_toronto = event.start_time.in_time_zone("America/Toronto")&.strftime("%Y%m%dT%H%M%S")
    
    "DTSTART:#{dtstart_toronto}\n#{rrule_without_dtstart}"
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

  def safe_to_time(value)
    return nil if value.nil?
    if value.respond_to?(:to_time)
      t = value.to_time
      t = t.utc unless t.utc?
      return t
    end
    Time.parse(value.to_s).utc # fallback
  rescue StandardError
    nil
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
end
