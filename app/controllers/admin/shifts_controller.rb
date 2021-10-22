# frozen_string_literal: true

class Admin::ShiftsController < AdminAreaController
  layout 'admin_area'

  before_action :set_default_space

  def index
    @spaces = Space.all.where(id: SpaceStaffHour.all.pluck(:space_id))
    @colors = {}
    StaffSpace.where(space_id: @default_space_id).each do |staff|
      @colors[staff.user.name] = "#" + "%06x" % (staff.user.id.hash & 0xffffff)
    end
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
      event['color'] = "#" + "%06x" % (staff.user.id.hash & 0xffffff)
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

