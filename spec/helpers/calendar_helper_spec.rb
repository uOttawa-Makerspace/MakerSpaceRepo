require 'rails_helper'

RSpec.describe CalendarHelper, type: :helper do
  
  describe "#parse_ics_calendar" do
    context "#parse_ics_calendar" do
      it "Should successfully pull ics information" do
        path = Rails.root.join("spec/support/assets/MakerRepo Test Calendar_d1ee6078f7d085e62d99150ed598526f1ead2068937d30d9b3a93b48e4b17dc0@group.calendar.google.com.ics")
        result = parse_ics_calendar(path)
      end
    end
  end
end
