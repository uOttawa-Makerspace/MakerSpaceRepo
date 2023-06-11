class TimePeriod < ApplicationRecord
  has_many :staff_availabilities

  default_scope -> { order(start_date: :desc) }

  def self.current
    tp =
      TimePeriod.where(
        "start_date <= ? AND end_date >= ?",
        Date.today,
        Date.today
      )

    time_period = nil
    time_period_smallest = 1_000_000

    tp.each do |t|
      if time_period_smallest > (t.start_date..t.end_date).count
        time_period_smallest = (t.start_date..t.end_date).count
        time_period = t
      end
    end

    time_period
  end
end
