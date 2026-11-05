# frozen_string_literal: true

require "rails_helper"

# The event sent to Google for each kind of Event: title, description, times, time zone and recurrence lines.
RSpec.describe GoogleCalendar::EventPayload do
  let(:space) { create(:space) }
  let(:creator) { create(:user, :staff) }

  def payload_for(attrs)
    described_class.new(create(:event, { space: space, created_by: creator }.merge(attrs))).build.to_h
  end

  it "builds a timed event" do
    expect(payload_for(title: "Open Lab", description: "Bring ID",
                       start_time: Time.utc(2027, 4, 1, 14), end_time: Time.utc(2027, 4, 1, 15))).to eq(
      attendees: [], description: "Bring ID", summary: "Open Lab",
      start: { date_time: "2027-04-01T10:00:00-04:00", time_zone: "America/Toronto" },
      end: { date_time: "2027-04-01T11:00:00-04:00", time_zone: "America/Toronto" }
    )
  end

  it "keeps only the RRULE and EXDATE lines of a recurring event" do
    payload = payload_for(title: "Weekly", description: "d", start_time: Time.utc(2027, 4, 1, 14),
                          end_time: Time.utc(2027, 4, 1, 15),
                          recurrence_rule: "DTSTART:20270401T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=TH;COUNT=3\nEXDATE:20270408T140000Z")
    expect(payload[:recurrence]).to eq(["RRULE:FREQ=WEEKLY;BYDAY=TH;COUNT=3", "EXDATE:20270408T140000Z"])
    expect(payload[:summary]).to eq("Weekly")
  end

  it "builds an all-day style event from midnight to midnight" do
    expect(payload_for(title: "Closed", description: "", start_time: Time.utc(2027, 4, 2, 4),
                       end_time: Time.utc(2027, 4, 3, 4))).to eq(
      attendees: [], description: "", summary: "Closed",
      start: { date_time: "2027-04-02T00:00:00-04:00", time_zone: "America/Toronto" },
      end: { date_time: "2027-04-03T00:00:00-04:00", time_zone: "America/Toronto" }
    )
  end

  it "appends the training details to the description of a training event" do
    training = create(:training, name_en: "Laser 101")
    event = create(:event, :training, space: space, created_by: creator, training: training, language: "fr",
                                      description: "Bring goggles")
    expect(described_class.new(event).build.description).to eq(
      "Bring goggles\n\nTraining: Laser 101\nLanguage: French\nCourse: #{event.course_name.name}"
    )
  end
end
