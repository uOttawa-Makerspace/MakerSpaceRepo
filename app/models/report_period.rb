# frozen_string_literal: true

# The days an admin report covers: a first and a last day, taken as whole days
# in the application time zone (Toronto). The window starts at the beginning of
# the first day and ends at the end of the last one, so a record made at any
# moment of either day is in the period. Both the on-screen reports and the
# downloads build their period here, so they all read dates and apply the
# same limits.
class ReportPeriod
  class Invalid < StandardError
  end

  EARLIEST_DAY = Date.new(2000, 1, 1)

  SEMESTERS = {
    "winter" => [[1, 1], [4, 30]],
    "summer" => [[5, 1], [8, 31]],
    "fall" => [[9, 1], [12, 31]]
  }.freeze

  attr_reader :first_day, :last_day

  # Two day strings, the start read before the end.
  def self.parse(start_text, end_text)
    first_day = read_day(start_text, "start")
    last_day = read_day(end_text, "end")
    new(first_day, last_day)
  end

  # A term ("winter", "summer" or "fall", in any letter case) of a year.
  def self.semester(term, year)
    year = year.to_i
    raise Invalid, "Invalid year" unless year > 0
    (first_month, first_mday), (last_month, last_mday) =
      SEMESTERS.fetch(term.to_s.downcase) { raise Invalid, "Invalid term" }
    new(Date.new(year, first_month, first_mday), Date.new(year, last_month, last_mday))
  end

  def self.read_day(text, label)
    Date.parse(text.to_s)
  rescue Date::Error
    raise Invalid, "Failed to parse #{label} date"
  end
  private_class_method :read_day

  def initialize(first_day, last_day)
    @first_day = first_day
    @last_day = last_day
    raise Invalid, "The end date is before the start date" if last_day < first_day
    unless first_day >= EARLIEST_DAY && last_day <= latest_day
      raise Invalid, "Dates must be between #{EARLIEST_DAY} and #{latest_day}"
    end
  end

  def window
    first_day.beginning_of_day..last_day.end_of_day
  end

  private

  # The end of next year, so the coming semesters can still be chosen.
  def latest_day
    Date.current.next_year.end_of_year
  end
end
