# frozen_string_literal: true

# The [start, end] pairs of a recurring booking: the first occurrence, then
# every week (or every month, for any other frequency) up to and including the
# end date. Each start is derived from the first one, never from the previous
# occurrence, so a monthly series that starts on the 31st books the last day of
# a short month and returns to the 31st afterwards. Starts advance in the
# first start's time zone, so they keep its wall-clock time across DST changes.
# Each end is its start plus the first occurrence's duration.
class BookingSeries
  include Enumerable

  def initialize(first_start, first_end, end_date, frequency)
    @first_start = first_start
    @duration = first_end - first_start
    @end_date = end_date
    @weekly = frequency.to_s == "weekly"
  end

  def each
    return to_enum(:each) unless block_given?

    index = 0
    loop do
      start_time = start_at(index)
      break if start_time.to_date > @end_date && index.positive?

      yield [start_time, start_time + @duration]
      index += 1
    end
  end

  private

  def start_at(index)
    @weekly ? @first_start + (7 * index).days : @first_start + index.months
  end
end
