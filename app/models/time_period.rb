class TimePeriod < ApplicationRecord
  has_many :staff_availabilities, dependent: :destroy

  validates :name, :start_date, :end_date, presence: true
  validate :end_date_not_before_start_date

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

  private

  def end_date_not_before_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must not be before the start date") if end_date < start_date
  end
end
