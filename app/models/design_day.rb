class DesignDay < ApplicationRecord
  has_many :design_day_schedules, dependent: :destroy
  has_many_attached :floorplans

  accepts_nested_attributes_for :design_day_schedules,
                                allow_destroy: true,
                                reject_if: :all_blank
  validates_associated :design_day_schedules

  validates :day, presence: true

  default_scope { order(day: :desc) }

  def self.instance
    any? ? first : create(day: Time.zone.today, sheet_key: '', is_live: false)
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

  def floorplan_urls
    floorplans.map(&:url) if floorplans.attached?
  end

  def floorplan_titles
    if floorplans.attached?
      floorplans.map { |floorplan| floorplan.metadata[:floorplan_title] }
    end
  end

  # Design day (1 or 2) each floorplan belongs to.
  # Floorplans uploaded before days existed default to day 1.
  def floorplan_days
    if floorplans.attached?
      floorplans.map do |floorplan|
        (floorplan.metadata[:floorplan_day].presence || 1).to_i
      end
    end
  end
end
