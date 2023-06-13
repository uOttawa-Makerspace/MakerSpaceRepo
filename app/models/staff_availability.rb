class StaffAvailability < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :time_period

  validates :day, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :time_period_id, presence: true

  def week_day
    Date::DAYNAMES[day.to_i]
  end
end
