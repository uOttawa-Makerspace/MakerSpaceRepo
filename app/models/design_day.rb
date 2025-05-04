class DesignDay < ApplicationRecord
  has_many :design_day_schedules, dependent: :destroy
  accepts_nested_attributes_for :design_day_schedules, allow_destroy: true, reject_if: :all_blank

  default_scope { order(day: :desc) }


  def self.instance
    any? ? first : create(day: Time.zone.today, sheet_key: "", is_live: false)
  end

  def can_be_published?
    is_live && sheet_key.present?
  end

  def semester
    case day.month
    when 1..4
      :winter
    when 5..8
      :summer
    when 9..12
      :fall
    end
  end

  # day.year
  delegate :year, to: :day
end
