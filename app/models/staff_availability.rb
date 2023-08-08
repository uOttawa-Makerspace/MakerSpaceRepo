class StaffAvailability < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :time_period

  validates :time_period_id, presence: true

  validates :start_time, :end_time, :day, presence: true, if: :recurring?
  validates :start_datetime, :end_datetime, presence: true, unless: :recurring?

  def week_day
    Date::DAYNAMES[day.to_i]
  end
end
