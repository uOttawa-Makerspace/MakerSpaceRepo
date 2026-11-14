# What an edit from a calendar dialog does to a record's times. The dialog's fields are Toronto wall-clock times, so
# when they are as the dialog filled them (`keep`) the stored instants stay: a field cannot say which 01:30 of the
# night the clocks go back it is, or how long an occurrence there lasts.
module Reschedulable
  # The start and end after an edit: its own when `keep`, else the posted ones; for "update all" on a `series`, its
  # own start date at the posted clock time, for the posted length.
  def times_after_update(posted_start, posted_end, keep:, series: false)
    return [start_time, end_time] if keep
    return [posted_start, posted_end] unless series

    start = on_date_at_clock_time(start_time, posted_start)
    [start, start + (posted_end - posted_start).to_i]
  end

  # For "update this" on a series: the instant to exclude, and the start and end of the one-off that replaces it.
  # When `keep`, they are those of the occurrence the dialog was opened on (the one nearest the posted start, which
  # the dialog's wall-clock fields name only to the hour); otherwise the posted times, excluding the posted date at
  # the series' clock time.
  def occurrence_after_update(posted_start, posted_end, keep:)
    occurrence = keep && occurrence_near(posted_start)
    return [on_date_at_clock_time(posted_start, start_time), posted_start, posted_end] unless occurrence

    [occurrence.starts_at, occurrence.starts_at, occurrence.ends_at]
  end

  private

  def occurrence_near(instant)
    window = CalendarWindow.new(instant - 1.day, instant + 1.day)
    RecurringSeries.for_record(self).occurrences_in(window).min_by { |occurrence| (occurrence.starts_at - instant).abs }
  end

  # The date of `date` at the clock time of `clock`, both read in Toronto time (a series keeps its Toronto clock time
  # across clock changes and late evenings, which are already the next day in UTC).
  def on_date_at_clock_time(date, clock)
    time = clock.in_time_zone(RecurrenceRule::ZONE)
    date.in_time_zone(RecurrenceRule::ZONE).change(hour: time.hour, min: time.min, sec: time.sec)
  end
end
