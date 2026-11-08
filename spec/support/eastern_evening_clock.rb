# frozen_string_literal: true

# Tag an example group `:eastern_evening` to run each of its examples at 19:30
# Eastern, when the UTC date is already tomorrow's. The factories must use the
# app zone (Date.current, Time.current), so records they build stay valid then.
module EasternEveningClock
  NOW = ActiveSupport::TimeZone["Eastern Time (US & Canada)"].local(2026, 11, 7, 19, 30)
end

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers, :eastern_evening

  config.around(:each, :eastern_evening) do |example|
    travel_to(EasternEveningClock::NOW)
    example.run
  ensure
    travel_back
  end
end
