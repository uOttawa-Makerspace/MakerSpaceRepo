class SpaceStaffHour < ApplicationRecord
  belongs_to :space

  def week_day
    Date::DAYNAMES[day.to_i]
  end
end
