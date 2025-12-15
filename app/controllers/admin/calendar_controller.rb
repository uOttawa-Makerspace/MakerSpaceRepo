class Admin::CalendarController < AdminAreaController
  layout "admin_area"

  def index
    @spaces =
      Space.all.where(
        id: StaffSpace.where(user_id: current_user.id).pluck(:space_id)
      )
    @space_id = @user.space_id || Space.first.id

    @colors = StaffSpace
      .includes(:user)
      .where(space_id: @space_id)
      .map do |staff_space|
        {
          id: staff_space.user.id,
          name: staff_space.user.name,
          username: staff_space.user.username,
          color: staff_space.color
        }
    end
    .sort_by { |user| user[:name].downcase }
    flash[:alert] = "You are not assigned to any spaces." if @spaces.empty?
  end

  def unavailabilities_json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    staff_user_ids = StaffSpace.where(space_id: params[:id]).pluck(:user_id)
    
    result = User
               .where(id: staff_user_ids, role: ['admin', 'staff'])
               .order(name: :desc).map do |staff|
      local_unavails = StaffUnavailability.where(user_id: staff.id).map do |u| 

        duration = (u.end_time.to_time - u.start_time.to_time) * 1000

        rrule_data = helpers.date_formatted_recurrence_rule(u)

        {
          id: u.id,
          title: "🚫 #{staff.name} - #{u.title}",
          start: u.start_time&.in_time_zone("America/Toronto")&.strftime("%Y-%m-%dT%H:%M:%S"),
          end: u.end_time&.in_time_zone("America/Toronto")&.strftime("%Y-%m-%dT%H:%M:%S"),
          **(u.recurrence_rule.present? ? { rrule: rrule_data, duration: duration } : {}),
          allDay: u.start_time.to_time == u.end_time.to_time - 1.day,
          extendedProps: {
            name: staff.name,
            description: u.description
          },
          className: "unavailability"
        }
      end

      ics_unavails = staff.staff_external_unavailabilities.flat_map do |external|
        parsed = helpers.parse_ics_calendar(
          external.ics_url,
          name: "#{staff.name} External Unavailability",
        )

        parsed.flat_map do |calendar|
          calendar[:events].map do |event|
            event.merge(title: "🚫 #{staff.name} - #{event[:title]}", className: "unavailability")
          end
        end
      end

      {
        id: staff.id,
        # for users with no unavails, we pull the name from here
        name: staff.name,
        color: StaffSpace.find_by(user_id: staff.id, space_id: params[:id])&.color,
        unavailabilities: local_unavails + ics_unavails
    }
    end

    render json: result
  end

  def imported_calendars_json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    calendars = StaffNeededCalendar.where(space_id: params[:id])
    all_calendars = calendars.flat_map do |calendar_record|
      helpers.parse_ics_calendar(
        calendar_record.calendar_url,
        name: calendar_record.name.presence || "Unnamed Calendar",
        color: calendar_record.color
      )
    end

    render json: all_calendars
  end

  def update_color
    if params[:user_id].present? &&
         StaffSpace.where(
           user_id: params[:user_id],
           space_id: @user.space_id
         ).present? && params[:color].present?
      staff_space =
        StaffSpace.where(
          user_id: params[:user_id],
          space_id: @user.space_id
        ).first
      return flash[:notice] = "Color updated successfully" if staff_space.update(color: params[:color])
    end

    flash[:alert] = "An error occurred, try again later."
  end


  private

  def set_default_space
    @space_id = current_user.space_id || Space.first.id
  end
end
