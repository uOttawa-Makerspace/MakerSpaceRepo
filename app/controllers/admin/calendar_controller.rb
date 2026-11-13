class Admin::CalendarController < AdminAreaController
  include CalendarWindowed
  layout "admin_area"

  before_action :require_space_id, only: %i[unavailabilities_json imported_calendars_json]

  def index
    @spaces = Space.where(id: StaffSpace.where(user_id: current_user.id).select(:space_id))
    @space_id = @user.space_id || Space.first&.id
    @colors = StaffSpace.includes(:user).where(space_id: @space_id).map do |staff_space|
      { id: staff_space.user.id, name: staff_space.user.name, username: staff_space.user.username, color: staff_space.color }
    end.sort_by { |user| user[:name].downcase }
    flash[:alert] = "You are not assigned to any spaces." if @spaces.empty?
    load_sidebar
  end

  # Per staff member of the space: their unavailabilities in the window (CalendarWindow), stored ones and those of
  # their external calendars. With no window, all of them (the event dialog reads them that way).
  def unavailabilities_json
    window = CalendarWindow.from_params(params)
    colors = StaffSpace.colors_in(params[:id])
    staff = StaffSpace.calendar_staff(params[:id]).includes(:staff_external_unavailabilities).order(name: :desc)
    stored = window.records(StaffUnavailability.where(user_id: staff.map(&:id))).group_by(&:user_id)
    render json: staff.map { |member|
      rows = stored.fetch(member.id, []).map { |unavailability| unavailability.calendar_row(member.name) }
      { id: member.id, name: member.name, color: colors[member.id], unavailabilities: rows + external_rows(member, window) }
    }
  end

  # The space's imported calendars, with their entries in the window (CalendarWindow).
  def imported_calendars_json
    window = CalendarWindow.from_params(params)
    render json: StaffNeededCalendar.where(space_id: params[:id]).flat_map { |calendar|
      helpers.parse_ics_calendar(calendar.calendar_url, name: calendar.display_name, color: calendar.color, window: window)
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

  def require_space_id
    render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?
  end

  # The calendar shows the space the space picker shows: the admin's own space when it is offered, else the first
  # one. Its sidebar lists its event types, its staff and its imported calendars.
  def load_sidebar
    @calendar_space_id = (@spaces.find_by(id: @space_id) || @spaces.first)&.id
    return if @calendar_space_id.nil?

    @hidden = %i[hidden_staff hidden_staff_events hidden_events hidden_calendars].index_with { |param| params[param].to_s.split(",") }
    @event_types = Event.types_in(@calendar_space_id)
    @sidebar_staff = StaffSpace.calendar_sidebar(@calendar_space_id)
    @imported_calendars = StaffNeededCalendar.where(space_id: @calendar_space_id).linked
  end

  def external_rows(staff, window)
    staff.staff_external_unavailabilities.flat_map do |external|
      calendars = helpers.parse_ics_calendar(external.ics_url, name: "#{staff.name} External Unavailability", window: window)
      calendars.flat_map { |calendar| calendar[:events].map { |event| event.merge(title: "🚫 #{staff.name} - #{event[:title]}", className: "unavailability") } }
    end
  end

  def render_color_error(key)
    render json: { status: "error", error: I18n.t(key) }, status: :unprocessable_entity
  end
end
