require 'rails_helper'

RSpec.describe CalendarHelper, type: :helper do
  
  describe "#parse_ics_calendar" do
    context "#parse_ics_calendar" do
      it "Should successfully pull ics information" do
        result = parse_ics_calendar("/spec/support/assets/MakerRepo Test Calendar_d1ee6078f7d085e62d99150ed598526f1ead2068937d30d9b3a93b48e4b17dc0@group.calendar.google.com.ics")
        binding.pry
      end
    end
  end
end
