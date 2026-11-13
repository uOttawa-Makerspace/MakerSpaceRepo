# What an edit from a calendar dialog does to a record's times. The dialog's fields are Toronto wall-clock times, so
# when they are as the dialog filled them (`keep`) the stored instants stay: a field cannot say which 01:30 of the
# night the clocks go back it is, or how long an occurrence there lasts.
module Reschedulable
  # The date of `keep_date` at the clock time of `keep_time`, both read in Toronto time (a series keeps its Toronto
  # clock time across clock changes and late evenings, which are already the next day in UTC).
  def self.combine_date_and_time(keep_date, keep_time)
    time = keep_time.in_time_zone(RecurrenceRule::ZONE)
    keep_date.in_time_zone(RecurrenceRule::ZONE).change(hour: time.hour, min: time.min, sec: time.sec)
  end

  # The start and end after an edit: its own when `keep`, else the posted ones; for "update all" on a `series`, its
  # own start date at the posted clock time, for the posted length.
  def times_after_update(posted_start, posted_end, keep:, series: false)
    return [start_time, end_time] if keep
    return [posted_start, posted_end] unless series

    start = Reschedulable.combine_date_and_time(start_time, posted_start)
    [start, start + (posted_end - posted_start).to_i]
  end

  # The start of the series' occurrence on the date of `posted_start`: that date at the series' clock time.
  def occurrence_start_on(posted_start) = Reschedulable.combine_date_and_time(posted_start, start_time)
end
