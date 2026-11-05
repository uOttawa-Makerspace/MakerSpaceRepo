# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe GoogleCalendar::DuplicateEventReport do
  let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil) }
  let(:space) { create(:space) }
  let(:start_time) { Time.utc(2027, 4, 1, 14) }
  let!(:event) do
    create(:event, space: space, title: "Open Lab", google_event_id: "mine", start_time: start_time, end_time: start_time + 1.hour)
  end

  def item(id, summary, start)
    Google::Apis::CalendarV3::Event.new(
      id: id, summary: summary, start: Google::Apis::CalendarV3::EventDateTime.new(date_time: start.iso8601)
    )
  end

  def stub_listing(*items)
    allow(service).to receive(:list_events)
      .and_return(Google::Apis::CalendarV3::Events.new(items: items, next_page_token: nil))
  end

  it "lists a Google event with the same title and start but another id, and leaves the owned one out" do
    stub_listing(item("mine", "Open Lab", start_time), item("orphan", "Open Lab", start_time),
                 item("other", "Other", start_time))
    expect(service).not_to receive(:delete_event)

    rows = described_class.new(service).rows

    expect(rows.map(&:google_event_id)).to eq(["orphan"])
    expect(rows.first.summary).to eq("Open Lab")
    expect(rows.first.start).to eq(start_time)
  end

  it "does not report an event that another stored event owns" do
    create(:event, space: space, title: "Open Lab", google_event_id: "twin", start_time: start_time, end_time: start_time + 1.hour)
    stub_listing(item("twin", "Open Lab", start_time))
    expect(described_class.new(service).rows).to be_empty
  end

  describe "google_calendar:duplicate_events" do
    before do
      Rails.application.load_tasks unless Rake::Task.task_defined?("google_calendar:duplicate_events")
      allow(GoogleCalendar::EventPublisher).to receive(:service).and_return(service)
      Rake::Task["google_calendar:duplicate_events"].reenable
    end

    it "prints the id, summary and start of each possible duplicate and changes nothing" do
      stub_listing(item("orphan", "Open Lab", start_time))
      expect(service).not_to receive(:delete_event)
      expect(service).not_to receive(:update_event)
      expect(service).not_to receive(:insert_event)

      expect { Rake::Task["google_calendar:duplicate_events"].invoke }
        .to output(/orphan\tOpen Lab\t2027-04-01T14:00:00Z\n1 possible duplicate/).to_stdout
      expect(event.reload.google_event_id).to eq("mine")
    end
  end
end
