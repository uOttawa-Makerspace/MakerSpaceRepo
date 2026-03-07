require 'rails_helper'

RSpec.describe CalendarHelper, type: :helper do

  let(:tz) { ActiveSupport::TimeZone["America/Toronto"] }
  
  describe "#parse_ics_calendar" do
    context "#parse_ics_calendar" do
      it "Should successfully pull ics information" do
        path = Rails.root.join("spec/support/assets/MakerRepo Test Calendar_d1ee6078f7d085e62d99150ed598526f1ead2068937d30d9b3a93b48e4b17dc0@group.calendar.google.com.ics")
        result = parse_ics_calendar(path)
      end
    end
  end

  describe '#combine_date_and_time' do
    it 'preserves wall-clock time across EST→EDT' do
      est_date = tz.parse("2025-01-15 09:00:00")  # EST
      edt_time = tz.parse("2025-06-15 13:00:00")  # EDT
      result = helper.combine_date_and_time(est_date, edt_time)
      local = result.in_time_zone(tz)
      expect(local.hour).to eq(13)
      expect(local.day).to eq(15)
      expect(local.month).to eq(1)
    end

    it 'preserves wall-clock time across EDT to EST' do
      edt_date = tz.parse("2025-06-15 09:00:00")
      est_time = tz.parse("2025-01-15 13:00:00")
      result = helper.combine_date_and_time(edt_date, est_time)
      local = result.in_time_zone(tz)
      expect(local.hour).to eq(13)
      expect(local.month).to eq(6)
    end
  end

  describe '#date_formatted_recurrence_rule' do
    it 'outputs floating local DTSTART without Z suffix' do
      event = build(:event,
        start_time: tz.parse("2025-01-15 13:00:00").utc,
        end_time: tz.parse("2025-01-15 15:00:00").utc,
        recurrence_rule: "DTSTART:20250115T180000Z\nRRULE:FREQ=DAILY;COUNT=3"
      )
      result = helper.date_formatted_recurrence_rule(event)
      expect(result).to include("DTSTART:20250115T130000")
      expect(result).not_to include("DTSTART:20250115T130000Z")
      expect(result).not_to include("DTSTART:20250115T180000")
    end

    it 'converts UNTIL from UTC to floating local' do
      event = build(:event,
        start_time: tz.parse("2025-01-15 13:00:00").utc,
        end_time: tz.parse("2025-01-15 15:00:00").utc,
        recurrence_rule: "DTSTART:20250115T180000Z\nRRULE:FREQ=DAILY;UNTIL=20250120T180000Z"
      )
      result = helper.date_formatted_recurrence_rule(event)
      expect(result).not_to match(/\d{8}T\d{6}Z/)  # No Z timestamps
    end
  end

  describe '#parse_rrule_and_dtstart' do
    it 'parses UTC DTSTART correctly' do
      _, dtstart, _ = helper.parse_rrule_and_dtstart(
        "DTSTART:20250115T180000Z\nRRULE:FREQ=DAILY;COUNT=3"
      )
      expect(dtstart).to eq(Time.parse("2025-01-15 18:00:00 UTC"))
    end

    it 'parses floating local DTSTART as America/Toronto' do
      _, dtstart, _ = helper.parse_rrule_and_dtstart(
        "DTSTART:20250115T130000\nRRULE:FREQ=DAILY;COUNT=3"
      )
      local = dtstart.in_time_zone(tz)
      expect(local.hour).to eq(13)
    end
  end
end