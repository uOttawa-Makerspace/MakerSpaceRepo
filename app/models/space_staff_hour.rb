class SpaceStaffHour < ApplicationRecord
  belongs_to :space

  validates :day, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true

  def week_day
    Date::DAYNAMES[day.to_i]
  end
end
