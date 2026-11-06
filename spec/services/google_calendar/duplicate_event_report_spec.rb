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

  describe "leftovers of a moved event" do
    let(:mtc) { create(:space, name: "MTC") }
    let(:mtc_calendar) { "c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com" }
    let(:test_calendar) { "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com" }

    it "flags a Google event whose id belongs to a stored event of another calendar, even with no match on title" do
      event.update_columns(space_id: mtc.id)
      allow(service).to receive(:list_events).with(test_calendar, anything)
        .and_return(Google::Apis::CalendarV3::Events.new(items: [item("mine", "Old title", start_time + 1.day)]))
      allow(service).to receive(:list_events).with(mtc_calendar, anything)
        .and_return(Google::Apis::CalendarV3::Events.new(items: [item("mine", "Open Lab", start_time)]))

      rows = described_class.new(service).rows

      expect(rows.map { |r| [r.calendar_id, r.google_event_id, r.reason] }).to eq([[test_calendar, "mine", :leftover]])
    end

    it "labels a same-title copy as a copy" do
      stub_listing(item("orphan", "Open Lab", start_time))
      expect(described_class.new(service).rows.map(&:reason)).to eq([:copy])
    end
  end

  it "reads every page of the listing" do
    first = Google::Apis::CalendarV3::Events.new(items: [item("orphan", "Open Lab", start_time)], next_page_token: "p2")
    second = Google::Apis::CalendarV3::Events.new(items: [item("orphan2", "Open Lab", start_time)], next_page_token: nil)
    allow(service).to receive(:list_events).with(anything, hash_including(page_token: nil)).and_return(first)
    allow(service).to receive(:list_events).with(anything, hash_including(page_token: "p2")).and_return(second)

    expect(described_class.new(service).rows.map(&:google_event_id)).to eq(%w[orphan orphan2])
  end

  it "ignores a listing without items and an all-day Google event that has no start time" do
    all_day = Google::Apis::CalendarV3::Event.new(
      id: "allday", summary: "Open Lab", start: Google::Apis::CalendarV3::EventDateTime.new(date: "2027-04-01")
    )
    no_start = Google::Apis::CalendarV3::Event.new(id: "nostart", summary: "Open Lab")
    allow(service).to receive(:list_events)
      .and_return(Google::Apis::CalendarV3::Events.new(items: [all_day, no_start], next_page_token: nil))
    expect(described_class.new(service).rows).to be_empty

    allow(service).to receive(:list_events).and_return(Google::Apis::CalendarV3::Events.new(next_page_token: nil))
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
        .to output(/orphan\tOpen Lab\t2027-04-01T14:00:00Z\tcopy\n1 possible duplicate/).to_stdout
      expect(event.reload.google_event_id).to eq("mine")
    end
  end
end
