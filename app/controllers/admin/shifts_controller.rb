# frozen_string_literal: true

class Admin::ShiftsController < AdminAreaController
  layout 'admin_area'

  def index
    @spaces = Space.all.where(id: SpaceStaffHour.all.pluck(:space_id))
  end

  def get_availabilities
    default_space_id = if params[:space_id].present? && params[:space_id] != 'null' && Space.find(params[:space_id]).present?
      params[:space_id]
    else
      Space.find_by(name: 'Makerspace')
    end

    staff_availabilities = []

    StaffAvailability.where(user_id: StaffSpace.where(space_id: default_space_id).pluck(:user_id)).each do |staff|
      event = {}
      event['title'] = "#{staff.user.name} is unavailable"
      event['id'] = staff.id
      event['daysOfWeek'] = [staff.day]
      event['startTime'] = staff.start_time.strftime("%H:%M")
      event['endTime'] = staff.end_time.strftime("%H:%M")
      staff_availabilities << event
    end

    render json: staff_availabilities
  end

end

