require 'rails_helper'

RSpec.describe CalendarHelper, type: :helper do
  include ActiveSupport::Testing::TimeHelpers

  describe "#parse_ics_calendar" do
    let(:path) do
      Rails.root.join("spec/support/assets/MakerRepo Test Calendar_d1ee6078f7d085e62d99150ed598526f1ead2068937d30d9b3a93b48e4b17dc0@group.calendar.google.com.ics")
    end

    it "returns no calendars for a blank url" do
      expect(parse_ics_calendar(nil)).to eq([])
      expect(parse_ics_calendar("")).to eq([])
    end

    it "pulls the event out of the ICS file, grouped under the md5 of the source" do
      # the fixture's only event ended 2025-11-17; events older than two months are dropped
      travel_to(Time.utc(2025, 11, 20, 12, 0)) do
        result = parse_ics_calendar(path, name: "Maker", color: "#123456")

        expect(result.size).to eq(1)
        group = result.first
        expect(group[:id]).to eq(Digest::MD5.hexdigest(path.to_s))
        expect(group[:color]).to eq("#123456")
        expect(group[:events].size).to eq(1)

        event = group[:events].first
        expect(event).to include(
          id: "2bgvhuelmj9hk3e5dvrsfrl9ba@google.com",
          groupId: group[:id],
          title: "Apples",
          allDay: true,
          display: "auto"
        )
        expect(event[:extendedProps]).to eq(name: "Maker", description: nil)
        expect(event).not_to have_key(:rrule)
        # all-day dates are read as UTC midnight and rendered in Toronto
        expect(event[:start]).to eq("2025-11-15T19:00:00")
        expect(event[:end]).to eq("2025-11-16T19:00:00")
      end
    end

    it "drops events that ended more than two months ago" do
      travel_to(Time.utc(2026, 3, 1, 12, 0)) do
        expect(parse_ics_calendar(path).first[:events]).to eq([])
      end
    end

    it "generates a colour from the source when none is given" do
      travel_to(Time.utc(2025, 11, 20, 12, 0)) do
        color = parse_ics_calendar(path).first[:color]
        expect(color).to eq(generate_color_from_id(path.to_s))
        expect(color).to match(/\Argba\(\d+, \d+, \d+, 1\.0\)\z/)
      end
    end
  end
end
