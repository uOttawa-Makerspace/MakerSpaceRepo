# frozen_string_literal: true

# the booking specs book fixed 2027 dates. Bookings that start in the
# past are rejected, so those specs would break once the real clock
# passes their dates. Tag an example group `:booking_clock` to run each of its
# examples at BookingClock::NOW, a fixed Eastern midday well before every fixed
# date those specs use (midday, so the UTC date is the same as the local one).
#
# The clock is set without a block, so examples may still call `travel_to`
# themselves: a block call returns to BookingClock::NOW when it ends.
module BookingClock
  NOW = ActiveSupport::TimeZone["Eastern Time (US & Canada)"].local(2026, 12, 1, 12, 0)
end

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers, :booking_clock

  config.around(:each, :booking_clock) do |example|
    travel_to(BookingClock::NOW)
    example.run
  ensure
    travel_back
  end
end
