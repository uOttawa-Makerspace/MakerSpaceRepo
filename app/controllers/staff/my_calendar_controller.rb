class Staff::MyCalendarController < StaffAreaController
  layout "staff_area"

  def index
     @spaces =
      Space.all.where(
        id: StaffSpace.where(user_id: current_user.id).pluck(:space_id)
      )
    @space_id = @user.space_id || Space.first.id
  end

  def json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    events = Event.where(space_id: params[:id], draft: false).map do |event|        
        title = if event.title == event.event_type.capitalize && !event.event_assignments.empty?
          "#{if event.draft
                '✎ '
              end}#{event.event_type == 'training' ? "#{event.training.name} (#{event.course_name.name || ''} - #{event.language || ''})" : event.event_type.capitalize} for #{event.event_assignments.map do |ea|
ea.user.name end.join(", ")}"
        else 
          "#{'✎ ' if event.draft}#{event.title}"
        end

        # seconds to milliseconds because javascript
        duration = (event.end_time.to_time - event.start_time.to_time) * 1000

        background = if event.event_assignments.empty?
          "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);#{' opacity: 0.8;' if event.draft}"
        else
        "linear-gradient(to right, #{event.event_assignments.map.with_index do |ea, i|
c = StaffSpace.find_by(user_id: ea.user_id, space_id: params[:id])&.color
s = (100.0 / event.event_assignments.size) * i
e = (100.0 / event.event_assignments.size) * (i + 1)
"#{c} #{s}%, #{c} #{e}%" end.join(', ')});#{' opacity: 0.8;' if event.draft}"
        end


      {
        id: "event-#{event.id}",
        title: title,
        start: event.start_time.iso8601,
        end: event.end_time.iso8601,
        **(event.recurrence_rule.present? ? { rrule: event.recurrence_rule, duration: duration } : {}),
        allDay: event.start_time.to_time == event.end_time.to_time - 1.day,
        extendedProps: {
          name: event.event_type.capitalize,
          draft: event.draft,
          description: event.description,
          eventType: event.event_type,
          hasCurrentUser: event.event_assignments.any? { |assignment| assignment.user.id == current_user.id },
          background: background
        },
      }
    end

    render json: events
  end
end