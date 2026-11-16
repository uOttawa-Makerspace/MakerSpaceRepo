class StaffUnavailability < ApplicationRecord
  include Reschedulable
  belongs_to :user

  validates :start_time, :end_time, presence: true
  validate :start_time_must_be_before_end_time
  validates :recurrence_rule, recurrence_rule: true, if: :will_save_change_to_recurrence_rule?
  validate :weekly_frequency_must_contain_days

  def start_time_must_be_before_end_time
    return unless start_time.present? && end_time.present? && start_time >= end_time
      errors.add(:start_time, :before_end_time)
  end

  # Its occurrences in the window (a CalendarWindow) as the calendar pages draw them: `row` (title, page properties) with
  # each occurrence's times and id, plus what the dialogs edit it by: type, staff member, record id, whether an admin
  # made it, and a series' repeat (nil for a single entry). An imported (ICS) entry carries none of these.
  def feed_rows(window, row)
    repeating = recurrence_rule.present?
    series = RecurrenceRule.new(recurrence_rule, start_time).dialog_fields if repeating
    row = row.merge(extendedProps: row[:extendedProps].merge(eventType: "unavailability", userId: user_id, recordId: id,
                                                             isAdminCreated: title&.include?("(Admin)"), series: series))
    occurrences_in(window).map { |occurrence| occurrence.feed_row(id, row, repeating: repeating) }
  end

  # Its occurrences that overlap the window (a CalendarWindow), expanded by RecurringSeries.
  def occurrences_in(window) = RecurringSeries.for_record(self).occurrences_in(window)

  # The `occurrences` of a planned event that overlap an unavailability of each of `user_ids` (ids or users), by user id.
  def self.clashes(user_ids, occurrences)
    return {} if occurrences.empty?

    busy = occurrences_for(user_ids, CalendarWindow.new(occurrences.first.starts_at, occurrences.last.ends_at))
    busy.transform_values do |slots|
      occurrences.select { |occurrence| slots.any? { |slot| slot.overlaps?(occurrence) } }
    end
  end

  # The occurrences in the window of each of `user_ids`' stored unavailabilities and external calendars, by user id.
  def self.occurrences_for(user_ids, window)
    sources = window.records(where(user_id: user_ids)).to_a + StaffExternalUnavailability.where(user_id: user_ids).to_a
    sources.group_by(&:user_id).transform_values { |of_user| of_user.flat_map { |source| source.occurrences_in(window) } }
  end

  def weekly_frequency_must_contain_days
    if recurrence_rule.present? && recurrence_rule.include?("FREQ=WEEKLY") && !recurrence_rule.include?("BYDAY")
      errors.add(:recurrence_rule, :weekly_needs_days)
    end
  end
end
