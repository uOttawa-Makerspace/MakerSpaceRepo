class Admin::CalendarController < AdminAreaController
  layout "admin_area"

  def index
     @spaces =
      Space.all.where(
        id: StaffSpace.where(user_id: current_user.id).pluck(:space_id)
      )
    @space_id = @user.space_id || Space.first.id
  end

  def json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    staff_user_ids = StaffSpace.where(space_id: params[:id]).pluck(:user_id)
    
    result = User.where(id: staff_user_ids).map do |staff|
      {
        id: staff.id,
        name: staff.name,
        color: helpers.generate_color_from_id(staff.id),
        unavailabilities: StaffUnavailability.where(user_id: staff.id).map do |u| 
          {
            id: u.id,
            title: "#{staff.name} - #{u.title}",
            start_date: u.start_time,
            end_date: u.end_time,
            recurrence_rule: u.recurrence_rule,
            extendedProps: {
              description: u.description
            }
          }
        end
      }
    end

    render json: result
  end

  def ics_to_json
    ics_url = params[:url]
    name = params[:name].presence || "Unnamed Calendar"
    background_color = params[:background_color].presence || helpers.generate_color_from_id(ics_url) 
    text_color = params[:text_color].presence || "#ffffff"
    group_id = params[:groupId].presence || Digest::MD5.hexdigest(ics_url)
    
    return render json: { error: "Missing 'url' parameter" }, status: :bad_request if ics_url.blank?

    begin
      response = HTTParty.get(ics_url,  timeout: 10 )
      return render json: { error: "Failed to fetch ICS file" }, status: :bad_gateway unless response.success?

      calendars = ::Icalendar::Calendar.parse(response.body)
      events = calendars.flat_map do |calendar|
        calendar.events.map do |event|
          # Skip events that are fully in the past
          next if event.rrule.empty? && event.dtend < (Time.now.utc - 1.month)

          event_hash = {
                id: event.uid,
                groupId: group_id,
                title: event.summary,
                extendedProps: {
                  name: name,
                  description: event.description,
                },
                allDay: (true if event.dtstart.to_time == event.dtend.to_time - 1.day)

              }

              # Handle recurring events (seems a tad broken especially with old events and exdate stuff)
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
                  event_hash[:duration] = ActiveSupport::Duration.build(duration_seconds).iso8601
                end
              else
                # Non-recurring single event
                event_hash[:start] = event.dtstart.to_time.iso8601
                event_hash[:end] = event.dtend.to_time.iso8601 if event.dtend
              end

              event_hash
        end.compact
      end

      render json: { events: events, id: group_id, color: background_color, textColor: text_color }
    rescue StandardError => e
      render json: { error: "Error parsing ICS: #{e.message}" }, status: :internal_server_error
    end
  end

  private

  def set_default_space
    @space_id = current_user.space_id || Space.first.id
  end

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

    
    "DTSTART:#{schedule.start_time.strftime('%Y%m%dT%H%M%SZ')}\n" + "RRULE:#{schedule.rrules.first.to_ical}"
  end
end