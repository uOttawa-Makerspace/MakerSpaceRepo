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

  # The occurrences of this unavailability in the window (a CalendarWindow), as the calendar pages draw them: `row`
  # (the title and the page's own properties) with each occurrence's times and id, the record id the dialogs edit
  # and delete by, and what they show of a series' repeat (nil for a single entry).
  def feed_rows(window, row)
    repeating = recurrence_rule.present?
    series = RecurrenceRule.new(recurrence_rule, start_time).dialog_fields if repeating
    row = row.merge(extendedProps: row[:extendedProps].merge(recordId: id, series: series))
    RecurringSeries.for_record(self).occurrences_in(window).map { |occurrence| occurrence.feed_row(id, row, repeating: repeating) }
  end

  # The rows the admin calendar draws for this unavailability of `staff_name` in the window; with no window (the
  # event dialog), the one row of calendar_row.
  def calendar_rows(staff_name, window)
    return [calendar_row(staff_name)] if window == CalendarWindow::ALL

    feed_rows(window, title: "🚫 #{staff_name} - #{title}", extendedProps: { name: staff_name, title: title, description: description },
                      className: "unavailability")
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