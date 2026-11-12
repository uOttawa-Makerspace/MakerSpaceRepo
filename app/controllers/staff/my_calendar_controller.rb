class Staff::MyCalendarController < StaffAreaController
  layout "staff_area"

  def index
    @spaces = Space.all.where(
      id: StaffSpace.where(user_id: current_user.id).pluck(:space_id)
    )
    # Only a space the page offers can be selected; a stored space the user is no longer assigned to is skipped.
    @space_id = (@spaces.find_by(id: current_user.space_id) || @spaces.first)&.id
  end

  def json
    return render_calendar_error(:space_required, :bad_request) if params[:id].blank?

    # Staff read the schedule of the spaces they are assigned to (the spaces the page offers); admins read any.
    unless current_user.admin? || StaffSpace.exists?(user_id: current_user.id, space_id: params[:id])
      return render_calendar_error(:space_not_assigned, :forbidden)
    end

    events = Event.where(space_id: params[:id], draft: false)
    
    # Optional filters
    events = events.where(event_type: params[:event_type]) if params[:event_type].present?
    
    if params[:user_id].present?
      events = events.joins(:event_assignments)
                     .where(event_assignments: { user_id: params[:user_id] })
                     .distinct
    end
    
    # Date range
    start_date = parse_range_param(params[:start], Time.zone.now - 3.months)
    end_date = parse_range_param(params[:end], Time.zone.now + 3.months)
    return render_calendar_error(:invalid_date, :bad_request) if start_date.nil? || end_date.nil?

    formatted_events = []
    
    # Single events outside the date range are left out before anything is read from them.
    events = events.select { |event| event.recurrence_rule.present? || (event.start_time >= start_date && event.end_time <= end_date) }
    preload_assignments(events)

    events.each do |event|
      if event.recurrence_rule.present?
        # Expand recurring events
        expanded = expand_recurring_event(event, start_date, end_date)
        formatted_events.concat(expanded)
      else
        formatted_events << format_event(event)
        Rails.logger.info "Added single event #{event.id}"
      end
    end

    render json: formatted_events
  end

  private

  # The parsed time, the default when the param is absent, nil when it is not a date.
  def parse_range_param(value, default)
    return default if value.blank?

    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end

  def render_calendar_error(cause, status)
    render json: { error: I18n.t("errors.staff.my_calendar.#{cause}"), reference: error_reference }, status: status
  end

  def expand_recurring_event(event, start_date, end_date)
    # Bounded: rules stored before validation existed (e.g. MINUTELY)
    # must not pin a worker. Same caps as the /api/v1 shifts serializer.
    found = RecurringSeries.for_record(event).occurrences_starting_in(
      start_date..end_date, limit: Api::V1::ShiftEventSerializer::MAX_OCCURRENCES_PER_EVENT
    )
    found.occurrences.map do |occurrence|
      # The occurrence's own start in the id keeps ids unique within the series.
      format_event(event, occurrence.starts_at, occurrence.ends_at).merge(id: "event-#{event.id}-#{occurrence.starts_at.to_i}")
    end
  rescue => e
    # Report it (event id only), then fall back: return the
    # original event if within date range
    report_unexpected(e, event_id: event.id)
    event.start_time >= start_date && event.end_time <= end_date ? [format_event(event)] : []
  end

  # The assignments (and the staff behind them) of the events that are about to be formatted.
  def preload_assignments(events)
    ActiveRecord::Associations::Preloader.new(records: events, associations: { event_assignments: :user }).call
  end

  # Each staff member's colour in the requested space, read once per request.
  def space_colors
    @space_colors ||= StaffSpace.where(space_id: params[:id]).order(id: :desc).pluck(:user_id, :color).to_h
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
        c = space_colors[ea.user_id] || '#3788d8'
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
      allDay: CalendarTime.all_day?(start_time, end_time),
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