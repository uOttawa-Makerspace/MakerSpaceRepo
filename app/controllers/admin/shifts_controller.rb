# frozen_string_literal: true

class Admin::ShiftsController < AdminAreaController
  layout "admin_area"

  before_action :set_default_space
  before_action :set_shifts, only: %i[edit update destroy]

  def index
    @spaces = Space.all.where(id: SpaceStaffHour.all.pluck(:space_id))
    @colors = {}
    @space_id = @user.space_id || Space.first.id

    StaffSpace
      .where(space_id: @space_id)
      .each { |staff| @colors[staff.user.name] = [staff.id, staff.color] }
  end

  def shifts
    @staff =
      User.where(
        id: StaffSpace.where(space_id: @space_id).pluck(:user_id)
      ).pluck(:name, :id)
    @spaces = Space.all.where(id: SpaceStaffHour.all.pluck(:space_id))
    @colors = {}

    StaffSpace
      .where(space_id: @space_id)
      .each { |staff| @colors[staff.user.name] = [staff.id, staff.color] }
  end

  def create
    if params[:shift].present? && params[:user_id].present?
      @shift = Shift.new(shift_params.merge(space_id: @space_id))
      params[:user_id].each { |user_id| @shift.users << User.find(user_id) }
    elsif params[:start_datetime].present? &&
          params[:start_datetime].present? && params[:user_id].present?
      start_date = DateTime.parse(params[:start_datetime])
      end_date = DateTime.parse(params[:start_datetime])
      @shift =
        Shift.new(
          space_id: @space_id,
          start_datetime: start_date,
          end_datetime: end_date,
          reason: params[:reason]
        )
      @shift.users << User.where(id: params[:user_id])
    else
      respond_to do |format|
        format.html { render :new }
        format.json do
          render json: {
                   error: "Missing params"
                 },
                 status: :unprocessable_entity
        end
      end
    end

    respond_to do |format|
      if @shift.save
        format.html do
          redirect_to shifts_admin_shifts_path,
                      notice: "The shift has been successfully created."
        end
        format.json do
          render json: {
                   id: @shift.id,
                   name: @shift.return_event_title,
                   color: @shift.color(@space_id),
                   start: @shift.start_datetime,
                   end: @shift.end_datetime,
                   className:
                     @shift.users.first.name.strip.downcase.gsub(" ", "-")
                 }
        end
      else
        format.html { render :new }
        format.json do
          render json: @shift.errors, status: :unprocessable_entity
        end
      end
    end
  end

  def update
    if params[:shift].present?
      respond_to do |format|
        if @shift.update(shift_params)
          format.html do
            redirect_to shifts_admin_shifts_path,
                        notice: "The shift has been successfully updated."
          end
          format.json { render json: { status: "ok" } }
        else
          format.html { render :edit }
          format.json do
            render json: @shift.errors, status: :unprocessable_entity
          end
        end
      end
    elsif params[:start_datetime].present? && params[:end_datetime].present?
      start_date = DateTime.parse(params[:start_datetime])
      end_date = DateTime.parse(params[:end_datetime])

      respond_to do |format|
        if @shift.update(start_time: start_date, end_time: end_date)
          format.html do
            redirect_to shifts_admin_shifts_path,
                        notice: "The shift has been successfully updated."
          end
          format.json { render json: { status: "ok" }, status: :ok }
        else
          format.html { render :edit }
          format.json do
            render json: @shift.errors, status: :unprocessable_entity
          end
        end
      end
    else
      respond_to do |format|
        format.html { render :new }
        format.json do
          render json: {
                   error: "Missing params"
                 },
                 status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    @shift.destroy
    respond_to do |format|
      format.html do
        redirect_to staff_availabilities_path,
                    notice: "The shift has been successfully deleted."
      end
      format.json { head :no_content }
    end
  end

  def update_color
    if params[:id].present? && StaffSpace.find(params[:id]).present? &&
         params[:color].present?
      staff_space = StaffSpace.find(params[:id])
      if staff_space.update(color: params[:color])
        flash[:notice] = "Color updated successfully"
      else
        flash[:alert] = "Color could not be updated"
      end
    else
      flash[:alert] = "An error occurred, try again later."
    end
    redirect_to(
      (params[:shifts].present? ? shifts_admin_shifts_path : admin_shifts_path)
    )
  end

  def get_availabilities
    opacity = params[:transparent].present? ? 0.25 : 1
    staff_availabilities = []
    @space_id = params[:space_id] if params[:space_id].present?
    StaffAvailability
      .where(user_id: StaffSpace.where(space_id: @space_id).pluck(:user_id))
      .each do |staff|
        event = {}
        event["title"] = "#{staff.user.name} is unavailable"
        event["id"] = staff.id
        event["daysOfWeek"] = [staff.day]
        event["startTime"] = staff.start_time.strftime("%H:%M")
        event["endTime"] = staff.end_time.strftime("%H:%M")
        event["color"] = hex_color_to_rgba(
          staff.user.staff_spaces.find_by(space_id: @space_id).color,
          opacity
        )
        event["className"] = staff.user.name.strip.downcase.gsub(" ", "-")
        staff_availabilities << event
      end

    render json: staff_availabilities
  end

  def get_shifts
    shifts = []

    Shift
      .includes(:users)
      .where(
        "users.id": StaffSpace.where(space_id: @space_id).pluck(:user_id),
        space_id: @space_id
      )
      .each do |shift|
        event = {}
        event["title"] = shift.return_event_title
        event["id"] = shift.id
        event["start"] = shift.start_datetime
        event["end"] = shift.end_datetime
        event["color"] = hex_color_to_rgba(shift.color(@space_id), 1)
        event["className"] = shift.users.first.name.strip.downcase.gsub(
          " ",
          "-"
        )
        shifts << event
      end

    render json: shifts
  end

  def get_staff_needed
    staff_needed = []

    SpaceStaffHour
      .where(space_id: @space_id)
      .each do |shift|
        event = {}
        event["title"] = "Staff Needed"
        event["daysOfWeek"] = [shift.day]
        event["startTime"] = shift.start_time.strftime("%H:%M")
        event["endTime"] = shift.end_time.strftime("%H:%M")
        staff_needed << event
      end

    render json: staff_needed
  end

  def get_external_staff_needed
    render json:
             StaffNeededCalendar.where(space_id: @space_id).pluck(:calendar_url)
  end

  private

  def set_default_space
    @space_id = @user.space_id || Space.first.id
  end

  def set_shifts
    @shift = Shift.find(params[:id])
  end

  def hex_color_to_rgba(hex, opacity)
    rgb = hex.match(/^#(..)(..)(..)$/).captures.map(&:hex)
    "rgba(#{rgb.join(", ")}, #{opacity})"
  end

  def shift_params
    params.require(:shift).permit(
      :start_datetime,
      :end_datetime,
      :reason,
      :space_id,
      user_id: []
    )
  end
end
