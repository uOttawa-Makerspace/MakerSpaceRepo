class Staff::MyCalendarController < StaffAreaController
  layout "staff_area"

  def index
    @spaces = Space.all.where(
      id: StaffSpace.where(user_id: current_user.id).pluck(:space_id)
    )
    @space_id = current_user.space_id || @spaces.first.id
  end

  def json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    events = Event.where(space_id: params[:id], draft: false)
    
    # Optional filters
    events = events.where(event_type: params[:event_type]) if params[:event_type].present?
    
    if params[:user_id].present?
      events = events.joins(:event_assignments)
                     .where(event_assignments: { user_id: params[:user_id] })
                     .distinct
    end
    
    # Date range
    start_date = params[:start].present? ? Time.zone.parse(params[:start]) : Time.zone.now - 3.months
    end_date = params[:end].present? ? Time.zone.parse(params[:end]) : Time.zone.now + 3.months
    formatted_events = []
    
    events.each do |event|
      
      if event.recurrence_rule.present?
        # Expand recurring events
        expanded = expand_recurring_event(event, start_date, end_date)
        formatted_events.concat(expanded)
      else
        # Single events within date range
        if event.start_time >= start_date && event.end_time <= end_date
          formatted_events << format_event(event)
          Rails.logger.info "Added single event #{event.id}"
        end
      end
    end

    render json: formatted_events
  end

  private

  def expand_recurring_event(event, start_date, end_date)
    require 'ice_cube'
    
    expanded_events = []
    
    begin
      # Parse the iCalendar format recurrence rule
      rrule_string = event.recurrence_rule.to_s
      
      # Extract just the RRULE part (remove DTSTART line)
      rrule_line = rrule_string.lines.find { |line| line.start_with?('RRULE:') }
      
      if rrule_line.nil?
        # If no RRULE: prefix, assume the whole string is the rule
        rrule_line = rrule_string.include?('RRULE:') ? rrule_string : "RRULE:#{rrule_string}"
      end
      
      # Remove RRULE: prefix and whitespace
      rrule_clean = rrule_line.gsub('RRULE:', '').strip
      
      # Create schedule with event's actual start time
      schedule = IceCube::Schedule.new(event.start_time)
      
      # Parse and add the recurrence rule
      rule = IceCube::Rule.from_ical(rrule_clean)
      schedule.add_recurrence_rule(rule)
      
      # Get occurrences within date range
      # Use a larger buffer to ensure we catch all occurrences
      occurrences = schedule.occurrences_between(start_date, end_date)

      # Calculate duration
      duration = event.end_time - event.start_time
      
      occurrences.each_with_index do |occurrence, index|
        occurrence_end = occurrence + duration
        
        formatted_event = format_event(event, occurrence, occurrence_end)
        # Create unique ID using timestamp to avoid collisions
        formatted_event[:id] = "event-#{event.id}-#{occurrence.to_i}"
        
        expanded_events << formatted_event
      end
      
    rescue => e
      # Fallback: return the original event if within date range
      if event.start_time >= start_date && event.end_time <= end_date
        expanded_events << format_event(event)
      end
    end
    
    expanded_events
  end

  def format_event(event, start_time = nil, end_time = nil)
    start_time ||= event.start_time
    end_time ||= event.end_time
    
    title = if event.title == event.event_type.capitalize && !event.event_assignments.empty?
      "#{if event.draft then '✎ ' end}#{event.event_type == 'training' ? "#{event.training.name} (#{event.course_name.name || ''} - #{event.language || ''})" : event.event_type.capitalize} for #{event.event_assignments.map { |ea| ea.user.name }.join(", ")}"
    else 
      "#{'✎ ' if event.draft}#{event.title}"
    end

    background = if event.event_assignments.any?
      "linear-gradient(to right, #{event.event_assignments.map.with_index do |ea, i|
        c = StaffSpace.find_by(user_id: ea.user_id, space_id: params[:id])&.color || '#3788d8'
        s = (100.0 / event.event_assignments.size) * i
        e = (100.0 / event.event_assignments.size) * (i + 1)
        "#{c} #{s}%, #{c} #{e}%"
      end.join(', ')});#{' opacity: 0.8;' if event.draft}"
    else
      '#3788d8'
    end

    {
      id: "event-#{event.id}",
      title: title,
      start: start_time.iso8601,
      end: end_time.iso8601,
      allDay: start_time.to_time == end_time.to_time - 1.day,
      extendedProps: {
        name: event.event_type.capitalize,
        draft: event.draft,
        description: event.description,
        eventType: event.event_type,
        hasCurrentUser: event.event_assignments.any? { |assignment| assignment.user.id == current_user.id },
        background: background
      }
    }
  end
end