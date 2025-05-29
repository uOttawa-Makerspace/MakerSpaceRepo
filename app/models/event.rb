class Event < ApplicationRecord
  belongs_to :created_by, class_name: 'User'
  belongs_to :space
  has_many :event_assignments, dependent: :destroy
  has_many :users, through: :event_assignments, source: :user

  validates :start_time, :end_time, :created_by_id, :space_id, :event_type, presence: true

  validate :start_time_must_be_before_end_time
  validate :weekly_frequency_must_contain_days

  private


  def start_time_must_be_before_end_time
    return unless start_time.present? && end_time.present? && start_time >= end_time
      errors.add(:start_time, "must be before the end time")
  end

  def weekly_frequency_must_contain_days
    if recurrence_rule.present? && recurrence_rule.include?("FREQ=WEEKLY") && !recurrence_rule.include?("BYDAY")
      errors.add(:recurrence_rule, "must include days of the week when using weekly frequency")
    end
  end
end