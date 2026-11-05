# frozen_string_literal: true

# Pins the system browser to the zone of the real users (America/Toronto) and
# freezes the server clock at noon of the current Eastern day, so a date the
# browser picks as "today" and a date the server computes as "today" are the
# same day whatever the time of the run or the zone of the container.
RSpec.shared_context "with the browser in Toronto time" do
  include ActiveSupport::Testing::TimeHelpers

  before do
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "America/Toronto")
    travel_to(Time.find_zone!("America/Toronto").now.change(hour: 12))
  end

  after { travel_back }
end
