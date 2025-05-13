# frozen_string_literal: true
require "date"

class Staff::SharedCalendarsController < StaffAreaController
  layout "staff_area"

  def index
     @spaces =
      Space.all.where(
        id: StaffSpace.where(user_id: current_user.id).pluck(:space_id)
      )
    @space_id = @user.space_id || Space.first.id
  end
 
  def get_calendars
    @calendars = SharedCalendar.where(
      space_id: @user.space_id || Space.first.id
    )

    render json: {
      calendars: @calendars.map do |calendar| 
        {
          name: calendar.name,
          url: calendar.url,
        }
      end
    }

  end

  private
  def set_default_space
    @space_id = current_user.space_id || Space.first.id
  end
end



