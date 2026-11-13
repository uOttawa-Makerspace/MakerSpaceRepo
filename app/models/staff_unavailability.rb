class StaffUnavailability < ApplicationRecord
  belongs_to :user

  validates :start_time, :end_time, presence: true
  validate :start_time_must_be_before_end_time
  validates :recurrence_rule, recurrence_rule: true, if: :will_save_change_to_recurrence_rule?
  validate :weekly_frequency_must_contain_days

  def start_time_must_be_before_end_time
    return unless start_time.present? && end_time.present? && start_time >= end_time
      errors.add(:start_time, :before_end_time)
  end

  # The row the admin calendar draws for this unavailability of `staff_name`, in Toronto wall time; a series also
  # carries its rule and its length in milliseconds, for the page to repeat.
  def calendar_row(staff_name)
    { id: id, title: "🚫 #{staff_name} - #{title}", start: toronto_wall(start_time), end: toronto_wall(end_time),
      **calendar_recurrence, allDay: CalendarTime.all_day?(start_time, end_time),
      extendedProps: { name: staff_name, title: title, description: description }, className: "unavailability" }
  end

  def weekly_frequency_must_contain_days
    if recurrence_rule.present? && recurrence_rule.include?("FREQ=WEEKLY") && !recurrence_rule.include?("BYDAY")
      errors.add(:recurrence_rule, :weekly_needs_days)
    end
  end

  private

  def calendar_recurrence
    return {} if recurrence_rule.blank?

    { rrule: RecurrenceRule.new(recurrence_rule, start_time).in_toronto_time, duration: (end_time.to_time - start_time.to_time) * 1000 }
  end

  def toronto_wall(time) = time.in_time_zone(RecurrenceRule::ZONE).strftime("%Y-%m-%dT%H:%M:%S")
end