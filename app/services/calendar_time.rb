# frozen_string_literal: true

# Wall-clock helpers for the FullCalendar JSON feeds (D-SP29).
module CalendarTime
  module_function

  # FullCalendar's allDay flag: the span is exactly one calendar day in the app
  # zone (23h or 25h on a DST change day). Computed on TimeWithZone values: the
  # old `start.to_time == end.to_time - 1.day` built "one day before the end" as a
  # zoned Ruby Time, which raises TZInfo::PeriodNotFound when that local time does
  # not exist (an end at 02:xx on the Monday after spring-forward), whereas
  # TimeWithZone shifts a nonexistent local time forward. Same answer otherwise.
  def all_day?(start_time, end_time)
    start_time.in_time_zone == end_time.in_time_zone - 1.day
  end
end
