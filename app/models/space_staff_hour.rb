class SpaceStaffHour < ApplicationRecord
  belongs_to :space
  has_one :TrainingLevel
  has_one :Course

  validates :day, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true

  def week_day
    Date::DAYNAMES[day.to_i]
  end
end
