# frozen_string_literal: true

class Admin::ShiftsController < AdminAreaController
  layout 'admin_area'

  before_action :set_default_space

  def index
    @spaces = Space.all.where(id: SpaceStaffHour.all.pluck(:space_id))
    @colors = {}

    StaffSpace.where(space_id: @default_space_id).each do |staff|
      @colors[staff.user.name] = [staff.id, staff.color]
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
    staff_availabilities = []

    StaffAvailability.where(user_id: StaffSpace.where(space_id: @default_space_id).pluck(:user_id)).each do |staff|
      event = {}
      event['title'] = "#{staff.user.name} is unavailable"
      event['id'] = staff.id
      event['daysOfWeek'] = [staff.day]
      event['startTime'] = staff.start_time.strftime("%H:%M")
      event['endTime'] = staff.end_time.strftime("%H:%M")
      event['color'] = staff.user.staff_spaces.find_by(space_id: @default_space_id).color
      staff_availabilities << event
    end

    render json: staff_availabilities
  end

  private

  def set_default_space
    @default_space_id = if params[:space_id].present? && params[:space_id] != 'null' && Space.find(params[:space_id]).present?
                         params[:space_id]
                       else
                         Space.find_by(name: 'Makerspace')
                        end
  end

end

