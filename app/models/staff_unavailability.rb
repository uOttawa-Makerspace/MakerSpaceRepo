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

  # The occurrences of this unavailability in the window (a CalendarWindow), as the calendar pages draw them: `row`
  # (the title and the page's own properties) with each occurrence's times and id, the record id the dialogs edit
  # and delete by, and what they show of a series' repeat (nil for a single entry).
  def feed_rows(window, row)
    repeating = recurrence_rule.present?
    series = RecurrenceRule.new(recurrence_rule, start_time).dialog_fields if repeating
    row = row.merge(extendedProps: row[:extendedProps].merge(recordId: id, series: series))
    occurrences_in(window).map { |occurrence| occurrence.feed_row(id, row, repeating: repeating) }
  end

  # Its occurrences that overlap the window (a CalendarWindow), expanded by RecurringSeries.
  def occurrences_in(window) = RecurringSeries.for_record(self).occurrences_in(window)

  def weekly_frequency_must_contain_days
    if recurrence_rule.present? && recurrence_rule.include?("FREQ=WEEKLY") && !recurrence_rule.include?("BYDAY")
      errors.add(:recurrence_rule, :weekly_needs_days)
    end
  end
end
