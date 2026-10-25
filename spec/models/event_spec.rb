# frozen_string_literal: true

require "rails_helper"

# Event model basics: validations, display_title, the Google Calendar
# callbacks (rails_helper stubs Event.upsert_event / delete_event /
# authorizer for every example, so callbacks are asserted as received calls)
# and the Google payload built by Event.upsert_event (Google service stubbed at
# the boundary).

RSpec.describe Event, type: :model do
  let(:space) { create(:space) }
  let(:creator) { create(:user, :staff) }

  def build_event(attrs = {})
    build(:event, { space: space, created_by: creator,
                    start_time: Time.utc(2027, 4, 1, 14, 0),
                    end_time: Time.utc(2027, 4, 1, 15, 0) }.merge(attrs))
  end

  describe "validations" do
    it "is valid with the factory defaults" do
      expect(build_event).to be_valid
    end

    it "requires start_time, end_time, created_by, space and event_type" do
      event = described_class.new
      expect(event).not_to be_valid
      expect(event.errors.attribute_names)
        .to include(:start_time, :end_time, :created_by_id, :space_id, :event_type, :created_by, :space)
    end

    it "requires the start to be before the end" do
      event = build_event(end_time: Time.utc(2027, 4, 1, 14, 0))
      expect(event).not_to be_valid
      expect(event.errors[:start_time]).to eq(["must be before the end time"])
    end

    it "requires a training for a published training event only" do
      expect(build_event(event_type: "training", draft: false)).not_to be_valid
      expect(build_event(event_type: "training", draft: false).tap(&:valid?).errors[:training_id])
        .to eq(["This field is required."])
      expect(build_event(event_type: "training", draft: true)).to be_valid
      expect(build_event(event_type: "training", draft: false, training: create(:training))).to be_valid
    end

    it "requires BYDAY for a weekly recurrence rule" do
      event = build_event(recurrence_rule: "DTSTART:20270401T140000Z\nRRULE:FREQ=WEEKLY;COUNT=3")
      expect(event).not_to be_valid
      expect(event.errors[:recurrence_rule]).to eq(["must include days of the week when using weekly frequency"])
      event.recurrence_rule = "DTSTART:20270401T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=TH;COUNT=3"
      expect(event).to be_valid
    end
  end

  describe "associations" do
    it "destroys its assignments and exposes the assigned users" do
      event = create(:event, space: space, created_by: creator)
      staff = create(:user, :staff)
      create(:event_assignment, event: event, user: staff)
      expect(event.users).to eq([staff])
      expect { event.destroy }.to change(EventAssignment, :count).by(-1)
    end
  end

  describe "#display_title" do
    it "returns the plain title when it is not the capitalized event type" do
      event = build_event(title: "Board meeting")
      expect(event.display_title).to eq("Board meeting")
    end

    it "prefixes drafts with the pencil marker unless asked not to" do
      event = build_event(title: "Board meeting", draft: true)
      expect(event.display_title).to eq("✎ Board meeting")
      expect(event.display_title(include_draft_indicator: false)).to eq("Board meeting")
    end

    it "keeps the event-type title when nobody is assigned" do
      expect(create(:event, space: space, created_by: creator, title: "Meeting").display_title).to eq("Meeting")
    end

    it "names the assigned staff for a default-titled event" do
      event = create(:event, space: space, created_by: creator, title: "Meeting")
      create(:event_assignment, event: event, user: create(:user, :staff, name: "Alex One"))
      create(:event_assignment, event: event, user: create(:user, :staff, name: "Bo Two"))
      expect(event.reload.display_title).to eq("Meeting for Alex One, Bo Two")
    end

    it "builds the training title from the training, course and language" do
      training = create(:training, name_en: "Laser 101")
      event = create(:event, :training, space: space, created_by: creator, title: "Training",
                                        training: training, language: "FR")
      create(:event_assignment, event: event, user: create(:user, :staff, name: "Alex One"))
      expect(event.reload.display_title)
        .to eq("Laser 101 (#{event.course_name.name} - FR) for Alex One")
    end

    it "falls back to the word Training when the training is missing" do
      event = create(:event, space: space, created_by: creator, event_type: "training", title: "Training", draft: true)
      create(:event_assignment, event: event, user: create(:user, :staff, name: "Alex One"))
      expect(event.reload.display_title).to eq("✎ Training for Alex One")
    end
  end

  describe "google callbacks" do
    it "pushes a published event to Google on save" do
      event = build_event(draft: false)
      event.save!
      expect(described_class).to have_received(:upsert_event).with(event)
    end

    it "does not push a draft on save" do
      build_event(draft: true).save!
      expect(described_class).not_to have_received(:upsert_event)
    end

    # WART(D-B48): only Google ClientErrors are rescued inside delete_event; with
    # the (stubbed) delete raising anything else the local destroy is aborted.
    it "keeps the local row when deleting the Google copy raises a non-client error" do
      event = create(:event, space: space, created_by: creator, google_event_id: "abc123")
      allow(described_class).to receive(:delete_event).and_raise(SocketError, "network down")
      expect { event.destroy }.to raise_error(SocketError)
      expect(described_class.exists?(event.id)).to be(true)
    end

    it "deletes the Google copy on destroy only when a google_event_id is present" do
      with_id = create(:event, space: space, created_by: creator, google_event_id: "abc123")
      without_id = create(:event, space: space, created_by: creator, google_event_id: nil)

      without_id.destroy
      expect(described_class).not_to have_received(:delete_event)

      with_id.destroy
      expect(described_class).to have_received(:delete_event).with(with_id)
    end
  end

  describe ".upsert_event (Google payload, service stubbed at the boundary)" do
    let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil) }
    let(:response) { instance_double(Google::Apis::CalendarV3::Event, id: "g-new-1") }

    # Events are created as drafts so the before_save callback stays quiet;
    # upsert_event is then called explicitly with the real implementation.
    before do
      allow(described_class).to receive(:upsert_event).and_call_original
      allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service)
    end

    it "inserts a new event on the test calendar with the display title and ISO times, then stores the Google id" do
      event = create(:event, :draft, space: space, created_by: creator, title: "Open Lab", description: "Bring ID",
                             start_time: Time.utc(2027, 4, 1, 14, 0), end_time: Time.utc(2027, 4, 1, 15, 0))
      captured = nil
      allow(service).to receive(:insert_event) { |calendar_id, gcal_event| captured = [calendar_id, gcal_event]; response }

      described_class.upsert_event(event)

      calendar_id, gcal = captured
      expect(calendar_id).to eq("c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com")
      expect(gcal.summary).to eq("Open Lab")
      expect(gcal.description).to eq("Bring ID")
      expect(gcal.start.date_time.to_s).to eq("2027-04-01T10:00:00-04:00")
      expect(gcal.start.time_zone).to eq("America/Toronto")
      expect(gcal.end.date_time.to_s).to eq("2027-04-01T11:00:00-04:00")
      expect(gcal.attendees).to eq([]) # attendees are never sent in the test env
      expect(event.reload.google_event_id).to eq("g-new-1")
    end

    it "picks the MTC and Makerspace calendars by space name" do
      mtc = create(:event, :draft, space: create(:space, name: "MTC"), created_by: creator)
      shop = create(:event, :draft, space: create(:space, name: "Makerspace"), created_by: creator)
      ids = []
      allow(service).to receive(:insert_event) { |calendar_id, _| ids << calendar_id; response }

      described_class.upsert_event(mtc)
      described_class.upsert_event(shop)

      expect(ids).to eq(["c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com",
                         "c_g1bk6ctpenjeko2dourrr0h6pc@group.calendar.google.com"])
    end

    it "updates an event that already has a google_event_id and sends only RRULE/EXDATE recurrence lines" do
      event = create(:event, :draft, space: space, created_by: creator, google_event_id: "g-1",
                             recurrence_rule: "DTSTART:20270401T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=TH;COUNT=3\nEXDATE:20270408T140000Z")
      captured = nil
      allow(service).to receive(:update_event) { |_cal, google_id, gcal_event| captured = [google_id, gcal_event]; nil }

      described_class.upsert_event(event)

      google_id, gcal = captured
      expect(google_id).to eq("g-1")
      expect(gcal.recurrence).to eq(["RRULE:FREQ=WEEKLY;BYDAY=TH;COUNT=3", "EXDATE:20270408T140000Z"])
    end

    it "appends the training details to the description of a training event" do
      training = create(:training, name_en: "Laser 101")
      event = create(:event, :training, :draft, space: space, created_by: creator, training: training,
                                        language: "fr", description: "Bring goggles")
      captured = nil
      allow(service).to receive(:insert_event) { |_cal, gcal_event| captured = gcal_event; response }

      described_class.upsert_event(event)

      expect(captured.description).to eq(
        "Bring goggles\n\nTraining: Laser 101\nLanguage: French\nCourse: #{event.course_name.name}"
      )
    end

    it "logs and swallows a Google client error on update" do
      event = create(:event, :draft, space: space, created_by: creator, google_event_id: "g-1")
      allow(service).to receive(:update_event).and_raise(Google::Apis::ClientError.new("gone"))
      expect { described_class.upsert_event(event) }.not_to raise_error
    end
  end
end
