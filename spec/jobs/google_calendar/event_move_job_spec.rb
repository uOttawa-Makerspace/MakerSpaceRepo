# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::EventMoveJob, type: :job do
  let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil) }
  let(:shop) { create(:space, name: "Makerspace") }
  let(:mtc) { create(:space, name: "MTC") }
  let(:shop_calendar) { "c_g1bk6ctpenjeko2dourrr0h6pc@group.calendar.google.com" }
  let(:mtc_calendar) { "c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com" }
  let(:event) { create(:event, space: mtc, title: "Open Lab", google_event_id: "abc123") }

  before { allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service) }

  def client_error(status) = Google::Apis::ClientError.new("failed", status_code: status)

  it "moves the Google event to the new calendar keeping its id, then updates it there" do
    calls = []
    allow(service).to receive(:move_event) { |*args| calls << [:move, *args] }
    allow(service).to receive(:update_event) { |cal, id, gcal| calls << [:update, cal, id, gcal.summary] }

    described_class.perform_now(event.id, shop_calendar)

    expect(calls).to eq([[:move, shop_calendar, "abc123", mtc_calendar], [:update, mtc_calendar, "abc123", "Open Lab"]])
  end

  it "ends with the event live in the first calendar after a move there and a move back" do
    event.update_columns(space_id: shop.id)
    in_google = { "abc123" => shop_calendar }
    allow(service).to receive(:move_event) do |from, id, to|
      raise client_error(404) unless in_google[id] == from

      in_google[id] = to
    end
    allow(service).to receive(:update_event) { |cal, id, _| raise client_error(404) unless in_google[id] == cal }
    allow(service).to receive(:insert_event).and_raise("a moved event must not be inserted")

    described_class.perform_now(event.id, shop_calendar)    # the event is already back in the shop: nothing to move
    described_class.perform_now(event.id, mtc_calendar)     # the earlier move to MTC runs late: not in MTC, so it is only updated

    expect(in_google).to eq("abc123" => shop_calendar)
  end

  it "moves out of the old calendar when the event has moved and moves again" do
    in_google = { "abc123" => shop_calendar }
    allow(service).to receive(:move_event) { |from, id, to| in_google[id] = to if in_google[id] == from }
    allow(service).to receive(:update_event)

    event.update_columns(space_id: mtc.id)
    described_class.perform_now(event.id, shop_calendar)
    expect(in_google).to eq("abc123" => mtc_calendar)

    event.update_columns(space_id: shop.id)
    described_class.perform_now(event.id, mtc_calendar)
    expect(in_google).to eq("abc123" => shop_calendar)
  end

  it "only pushes when the event is not in the old calendar (404)" do
    allow(service).to receive(:move_event).and_raise(client_error(404))
    allow(service).to receive(:update_event).and_raise(client_error(404))
    expect(service).to receive(:insert_event).with(mtc_calendar, having_attributes(id: "abc123"))

    described_class.perform_now(event.id, shop_calendar)
  end

  it "does not move when the old and the new calendar are the same" do
    expect(service).not_to receive(:move_event)
    expect(service).to receive(:update_event)
    described_class.perform_now(event.id, mtc_calendar)
  end

  it "reports a move refused for another reason and does not retry it" do
    allow(service).to receive(:move_event).and_raise(client_error(403))
    expect(service).not_to receive(:update_event)
    expect(Rails.error).to receive(:report).with(instance_of(Google::Apis::ClientError), hash_including(context: hash_including(event_id: event.id)))

    expect { described_class.perform_now(event.id, shop_calendar) }.not_to have_enqueued_job(described_class)
  end

  it "retries a server error" do
    allow(service).to receive(:move_event).and_raise(Google::Apis::ServerError.new("down", status_code: 503))
    expect { described_class.perform_now(event.id, shop_calendar) }.to have_enqueued_job(described_class).with(event.id, shop_calendar)
  end

  it "does nothing for a missing event or a draft" do
    draft = create(:event, :draft, space: mtc, google_event_id: "d1")
    expect(Google::Apis::CalendarV3::CalendarService).not_to receive(:new)
    described_class.perform_now(0, shop_calendar)
    described_class.perform_now(draft.id, shop_calendar)
  end
end
