class StaffAvailability < ApplicationRecord
  belongs_to :user

  validates :day, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true

  def week_day
    Date::DAYNAMES[day.to_i]
  end
end
