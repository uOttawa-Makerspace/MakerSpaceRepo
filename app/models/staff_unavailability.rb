class StaffUnavailability < ApplicationRecord
  belongs_to :user

  validates :start_time, :end_time, presence: true
  validate :start_time_must_be_before_end_time
  validates :recurrence_rule, recurrence_rule: true
  validate :weekly_frequency_must_contain_days

  def start_time_must_be_before_end_time
    return unless start_time.present? && end_time.present? && start_time >= end_time
      errors.add(:start_time, :before_end_time)
  end

  def weekly_frequency_must_contain_days
    if recurrence_rule.present? && recurrence_rule.include?("FREQ=WEEKLY") && !recurrence_rule.include?("BYDAY")
      errors.add(:recurrence_rule, :weekly_needs_days)
    end
  end
end