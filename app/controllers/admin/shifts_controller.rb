# frozen_string_literal: true

class Admin::ShiftsController < AdminAreaController
  layout 'admin_area'

  before_action :set_default_space
  before_action :set_shifts, only: %i[edit update destroy]

  def index
    @spaces = Space.all.where(id: SpaceStaffHour.all.pluck(:space_id))
    @colors = {}

    StaffSpace.where(space_id: @default_space_id).each do |staff|
      @colors[staff.user.name] = [staff.id, staff.color]
    end
  end

  def shifts
    @staff = User.where(id: StaffSpace.where(space_id: @default_space_id).pluck(:user_id)).pluck(:name, :id)
    @spaces = Space.all.where(id: SpaceStaffHour.all.pluck(:space_id))
    @colors = {}

    StaffSpace.where(space_id: @default_space_id).each do |staff|
      @colors[staff.user.name] = [staff.id, staff.color]
    end
  end

  def create
    if params[:shift].present?
      @shift = Shift.new(shift_params.merge(space_id: @default_space_id))
    elsif params[:start_datetime].present? && params[:start_datetime].present? && params[:user_id].present?
      start_date = DateTime.parse(params[:start_datetime])
      end_date = DateTime.parse(params[:start_datetime])
      @shift = Shift.new(user_id: params[:user_id], space_id: @default_space_id, start_datetime: start_date, end_datetime: end_date, reason: params[:reason])
    else
      respond_to do |format|
        format.html { render :new }
        format.json { render json: { "error": "Missing params" }, status: :unprocessable_entity }
      end
    end

    respond_to do |format|
      if @shift.save
        format.html { redirect_to shifts_admin_shifts_path, notice: 'The shift has been successfully created.' }
        format.json { render json: { id: @shift.id, name: "#{@shift.reason} for #{@shift.user.name}", color: @shift.user.staff_spaces.find_by(space_id: @default_space_id).color, start: @shift.start_datetime, end: @shift.end_datetime, className: @shift.user.name.strip.downcase.gsub(' ', '-') } }
      else
        format.html { render :new }
        format.json { render json: @shift.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    if params[:shift].present?
      respond_to do |format|
        if @shift.update(shift_params)
          format.html { redirect_to shifts_admin_shifts_path, notice: 'The shift has been successfully updated.' }
          format.json { render json: { "status": "ok" } }
        else
          format.html { render :edit }
          format.json { render json: @shift.errors, status: :unprocessable_entity }
        end
      end
    elsif params[:start_datetime].present? && params[:end_datetime].present?
      start_date = DateTime.parse(params[:start_datetime])
      end_date = DateTime.parse(params[:end_datetime])

      respond_to do |format|
        if @shift.update(start_time: start_date, end_time: end_date)
          format.html { redirect_to shifts_admin_shifts_path, notice: 'The shift has been successfully updated.' }
          format.json { render json: { "status": "ok" }, status: :ok }
        else
          format.html { render :edit }
          format.json { render json: @shift.errors, status: :unprocessable_entity }
        end
      end
    else
      respond_to do |format|
        format.html { render :new }
        format.json { render json: { "error": "Missing params" }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @shift.destroy
    respond_to do |format|
      format.html { redirect_to staff_availabilities_path, notice: 'The shift has been successfully deleted.' }
      format.json { head :no_content }
    end
  end

  def update_color
    if params[:id].present? && StaffSpace.find(params[:id]).present? && params[:color].present?
      staff_space = StaffSpace.find(params[:id])
      if staff_space.update(color: params[:color])
        flash[:notice] = 'Color updated successfully'
      else
        flash[:alert] = 'Color could not be updated'
      end
    else
      flash[:alert] = "An error occurred, try again later."
    end
    redirect_to admin_shifts_path
  end

  def get_availabilities
    opacity = params[:transparent].present? ? 0.25 : 1
    staff_availabilities = []

    StaffAvailability.where(user_id: StaffSpace.where(space_id: @default_space_id).pluck(:user_id)).each do |staff|
      event = {}
      event['title'] = "#{staff.user.name} is unavailable"
      event['id'] = staff.id
      event['daysOfWeek'] = [staff.day]
      event['startTime'] = staff.start_time.strftime("%H:%M")
      event['endTime'] = staff.end_time.strftime("%H:%M")
      event['color'] = hex_color_to_rgba(staff.user.staff_spaces.find_by(space_id: @default_space_id).color, opacity)
      event['className'] = staff.user.name.strip.downcase.gsub(' ', '-')
      staff_availabilities << event
    end

    render json: staff_availabilities
  end

  def get_shifts
    shifts = []

    Shift.where(user_id: StaffSpace.where(space_id: @default_space_id).pluck(:user_id), space_id: @default_space_id).each do |shift|
      event = {}
      event['title'] = "#{shift.reason} for #{shift.user.name}"
      event['id'] = shift.id
      event['start'] = shift.start_datetime
      event['end'] = shift.end_datetime
      event['color'] = hex_color_to_rgba(shift.user.staff_spaces.find_by(space_id: @default_space_id).color, 1)
      event['className'] = shift.user.name.strip.downcase.gsub(' ', '-')
      shifts << event
    end

    render json: shifts
  end

  private

  def set_default_space
    @default_space_id = if params[:space_id].present? && params[:space_id] != 'null' && Space.find(params[:space_id]).present?
                          params[:space_id]
                        else
                          Space.find_by(name: 'Makerspace').id
                        end
  end

  def set_shifts
    @shift = Shift.find(params[:id])
  end

  def hex_color_to_rgba(hex, opacity)
    rgb = hex.match(/^#(..)(..)(..)$/).captures.map(&:hex)
    "rgba(#{rgb.join(", ")}, #{opacity})"
  end

  def shift_params
    params.require(:shift).permit(:start_datetime, :end_datetime, :reason, :user_id, :space_id)
  end

end

