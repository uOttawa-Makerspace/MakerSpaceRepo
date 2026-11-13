class Admin::CalendarController < AdminAreaController
  layout "admin_area"

  rescue_from CalendarWindow::Invalid, with: ->(error) { render json: { error: error.message }, status: :bad_request }

  def index
    @spaces =
      Space.all.where(
        id: StaffSpace.where(user_id: current_user.id).pluck(:space_id)
      )
    @space_id = @user.space_id || Space.first&.id

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

  # Per staff member of the space: their unavailabilities in the window (CalendarWindow), stored ones and those of
  # their external calendars. With no window, all of them (the event dialog reads them that way).
  def unavailabilities_json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    window = CalendarWindow.from_params(params)
    colors = StaffSpace.where(space_id: params[:id]).pluck(:user_id, :color).to_h
    staff = calendar_staff(params[:id]).includes(:staff_external_unavailabilities).order(name: :desc)
    stored = window.records(StaffUnavailability.where(user_id: staff.map(&:id))).group_by(&:user_id)
    render json: staff.map { |member|
      rows = stored.fetch(member.id, []).map { |unavailability| stored_unavailability_row(unavailability, member) }
      { id: member.id, name: member.name, color: colors[member.id], unavailabilities: rows + external_unavailability_rows(member, window) }
    }
  end

  # The space's imported calendars, with their entries in the window (CalendarWindow).
  def imported_calendars_json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    window = CalendarWindow.from_params(params)
    render json: StaffNeededCalendar.where(space_id: params[:id]).flat_map { |calendar|
      helpers.parse_ics_calendar(calendar.calendar_url, name: imported_name(calendar), color: calendar.color, window: window)
    }
  end

  def update_color
    staff_space = StaffSpace.find_by(user_id: params[:user_id], space_id: @user.space_id) if params[:user_id].present?

    if params[:color].blank?
      render_color_error("errors.calendar.color_blank")
    elsif staff_space.nil?
      render_color_error("errors.calendar.staff_not_in_space")
    elsif staff_space.update(color: params[:color])
      render json: { status: "ok" }
    else
      render_color_error("errors.calendar.color_invalid")
    end
  end

  private

  # The staff whose unavailabilities the calendar shows: the space's staff and admins.
  def calendar_staff(space_id)
    User.where(id: StaffSpace.where(space_id: space_id).select(:user_id), role: %w[admin staff])
  end

  def stored_unavailability_row(unavailability, staff)
    {
      id: unavailability.id,
      title: "🚫 #{staff.name} - #{unavailability.title}",
      start: unavailability.start_time.in_time_zone(RecurrenceRule::ZONE).strftime("%Y-%m-%dT%H:%M:%S"),
      end: unavailability.end_time.in_time_zone(RecurrenceRule::ZONE).strftime("%Y-%m-%dT%H:%M:%S"),
      **stored_recurrence(unavailability),
      allDay: CalendarTime.all_day?(unavailability.start_time, unavailability.end_time),
      extendedProps: { name: staff.name, title: unavailability.title, description: unavailability.description },
      className: "unavailability"
    }
  end

  # The rule the page repeats a stored series by, and its length in milliseconds.
  def stored_recurrence(unavailability)
    return {} if unavailability.recurrence_rule.blank?

    { rrule: helpers.date_formatted_recurrence_rule(unavailability),
      duration: (unavailability.end_time.to_time - unavailability.start_time.to_time) * 1000 }
  end

  def external_unavailability_rows(staff, window)
    staff.staff_external_unavailabilities.flat_map do |external|
      calendars = helpers.parse_ics_calendar(external.ics_url, name: "#{staff.name} External Unavailability", window: window)
      calendars.flat_map do |calendar|
        calendar[:events].map { |event| event.merge(title: "🚫 #{staff.name} - #{event[:title]}", className: "unavailability") }
      end
    end
  end

  def imported_name(calendar) = calendar.name.presence || "Unnamed Calendar"

  def render_color_error(key)
    render json: { status: "error", error: I18n.t(key) }, status: :unprocessable_entity
  end
end
