# frozen_string_literal: true

# Wall-clock helpers for the FullCalendar JSON feeds.
module CalendarTime
  module_function

  # FullCalendar's allDay flag: the span starts at a local midnight and ends at
  # the next local midnight, in the app zone (a 23h or 25h span on a DST change
  # day). A span of several whole days is not flagged (as before). Computed on
  # TimeWithZone values, which never raise for a nonexistent local time (the old
  # `start.to_time == end.to_time - 1.day` raised TZInfo::PeriodNotFound for an
  # end at 02:xx on the Monday after spring-forward, and flagged any 24h span).
  def all_day?(start_time, end_time)
    start_time = start_time.in_time_zone
    end_time = end_time.in_time_zone
    start_time == start_time.beginning_of_day && end_time == start_time.tomorrow.beginning_of_day
  end
end
