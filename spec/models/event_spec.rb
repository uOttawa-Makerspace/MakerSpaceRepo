# frozen_string_literal: true

require "rails_helper"

# Event model basics: validations, display_title and the queueing of Google
# Calendar pushes (the model has no Google callbacks; the jobs are specced
# under spec/jobs/google_calendar).

RSpec.describe Event, type: :model do
  let(:space) { create(:space) }
  let(:creator) { create(:user, :staff) }

  def build_event(attrs = {})
    build(:event, { space: space, created_by: creator,
                    start_time: Time.utc(2027, 4, 1, 14, 0),
                    end_time: Time.utc(2027, 4, 1, 15, 0) }.merge(attrs))
  end

  describe "last editor" do
    it "is optional" do
      expect(build_event).to be_valid
      expect(build_event.updated_by).to be_nil
    end

    it "is a user, kept apart from the creator" do
      editor = create(:user, :admin)
      event = create(:event, space: space, created_by: creator, updated_by: editor)
      expect(event.reload).to have_attributes(created_by: creator, updated_by: editor)
    end
  end

  describe "#unpublish" do
    let(:admin) { create(:user, :admin) }

    it "makes the event a draft, clears its Google ids, records who did it and queues nothing" do
      event = create(:event, space: space, created_by: creator, draft: false, google_event_id: "abc", google_calendar_id: "cal")
      expect { expect(event.unpublish(by: admin)).to be(true) }.not_to have_enqueued_job
      expect(event.reload).to have_attributes(draft: true, google_event_id: nil, google_calendar_id: nil, updated_by: admin)
    end

    it "returns false and keeps the event published when it cannot be saved" do
      event = create(:event, space: space, created_by: creator, draft: false, google_event_id: "abc")
      allow(event).to receive(:update).and_return(false)
      expect(event.unpublish(by: admin)).to be(false)
      expect(event.reload).to have_attributes(draft: false, google_event_id: "abc")
    end
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

    it "leaves out an assignment whose user is gone from a default-titled event" do
      event = create(:event, space: space, created_by: creator, title: "Meeting")
      create(:event_assignment, event: event, user: create(:user, :staff, name: "Alex One"))
      orphan = create(:event_assignment, event: event, user: create(:user, :staff))
      orphan.update_column(:user_id, nil)
      expect(event.reload.display_title).to eq("Meeting for Alex One")
    end

    it "leaves out an assignment whose user is gone from a training title" do
      event = create(:event, :training, space: space, created_by: creator, title: "Training",
                                        training: create(:training, name_en: "Laser 101"), language: nil, course_name: nil)
      create(:event_assignment, event: event, user: create(:user, :staff, name: "Alex One"))
      orphan = create(:event_assignment, event: event, user: create(:user, :staff))
      orphan.update_column(:user_id, nil)
      expect(event.reload.display_title).to eq("Laser 101 for Alex One")
    end

    it "falls back to the word Training when the training is missing" do
      event = create(:event, space: space, created_by: creator, event_type: "training", title: "Training", draft: true)
      create(:event_assignment, event: event, user: create(:user, :staff, name: "Alex One"))
      expect(event.reload.display_title).to eq("✎ Training for Alex One")
    end
  end

  describe "Google Calendar" do
    it "does not call Google when an event is saved or destroyed" do
      expect(GoogleCalendar::EventPublisher).not_to receive(:service)
      event = build_event(draft: false, google_event_id: "abc123")
      event.save!
      event.update!(title: "Changed")
      event.destroy
      expect(GoogleCalendar::EventPushJob).not_to have_been_enqueued
      expect(GoogleCalendar::EventDeleteJob).not_to have_been_enqueued
    end

    describe "#push_to_google_later" do
      it "stores a Google id on a new event and queues one push" do
        event = create(:event, space: space, created_by: creator, google_event_id: nil)
        event.push_to_google_later
        expect(event.reload.google_event_id).to match(/\A[0-9a-v]{32}\z/)
        expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(event.id).exactly(:once)
      end

      it "records the push as pending and keeps it when the queue is down" do
        event = create(:event, space: space, created_by: creator, google_event_id: "abc123")
        allow(GoogleCalendar::EventPushJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionNotEstablished)
        expect { event.push_to_google_later }.not_to raise_error
        expect(GoogleCalendar::PendingChange.where(action: "push", event_id: event.id)).to exist
      end

      it "keeps the id an event already has" do
        event = create(:event, space: space, created_by: creator, google_event_id: "abc123")
        event.push_to_google_later
        expect(event.reload.google_event_id).to eq("abc123")
      end

      it "treats an empty id as none" do
        event = create(:event, space: space, created_by: creator, google_event_id: "")
        event.push_to_google_later
        expect(event.reload.google_event_id).to be_present
      end

      it "queues nothing for a draft" do
        event = create(:event, :draft, space: space, created_by: creator, google_event_id: nil)
        event.push_to_google_later
        expect(GoogleCalendar::EventPushJob).not_to have_been_enqueued
        expect(event.reload.google_event_id).to be_nil
      end
    end

    describe "#google_calendar" do
      it "is the recorded calendar when there is one, else the calendar of the space" do
        event = build_event
        expect(event.google_calendar).to eq("c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com")
        event.google_calendar_id = "recorded@group.calendar.google.com"
        expect(event.google_calendar).to eq("recorded@group.calendar.google.com")
      end
    end

    describe ".remove_from_google_later" do
      it "queues the removal with the Google id and the calendar id" do
        described_class.remove_from_google_later("abc123", "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com", 7)
        expect(GoogleCalendar::EventDeleteJob).to have_been_enqueued
          .with("abc123", "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com", 7)
      end

      it "queues nothing without a Google id" do
        described_class.remove_from_google_later(nil, "cal", 7)
        described_class.remove_from_google_later("", "cal", 7)
        expect(GoogleCalendar::EventDeleteJob).not_to have_been_enqueued
      end

      it "picks the MTC and Makerspace calendars by space name" do
        expect(GoogleCalendar::EventPublisher.calendar_id_for(create(:space, name: "MTC")))
          .to eq("c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com")
        expect(GoogleCalendar::EventPublisher.calendar_id_for(create(:space, name: "Makerspace")))
          .to eq("c_g1bk6ctpenjeko2dourrr0h6pc@group.calendar.google.com")
      end
    end
  end

  describe "#feed_row" do
    let(:alex) { create(:user, :staff, name: "Alex One") }
    let(:blair) { create(:user, :staff, name: "Blair Two") }

    it "draws a one-off event with no assignee as unassigned on grey" do
      event = create(:event, space: space, created_by: creator, event_type: "shift", title: "Desk", description: "Front",
                             start_time: Time.utc(2027, 4, 1, 14), end_time: Time.utc(2027, 4, 1, 15))
      expect(event.feed_row({})).to eq(
        id: "event-#{event.id}", title: "Desk", start: "2027-04-01T10:00:00-04:00", end: "2027-04-01T11:00:00-04:00",
        allDay: false,
        extendedProps: { name: "Shift", draft: false, description: "Front", eventType: "shift", trainingId: nil,
                         language: nil, course_name: nil, assignedUsers: [{ id: 0, name: "Unassigned" }],
                         background: "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);" }
      )
    end

    it "stripes each assignee's colour, grey for one without, and fades a draft" do
      event = create(:event, :draft, space: space, created_by: creator, start_time: Time.utc(2027, 4, 1, 14),
                                     end_time: Time.utc(2027, 4, 1, 15))
      create(:event_assignment, event: event, user: alex)
      create(:event_assignment, event: event, user: blair)
      row = event.reload.feed_row(alex.id => "#ff0000")
      expect(row[:extendedProps][:assignedUsers]).to eq([{ id: alex.id, name: "Alex One" }, { id: blair.id, name: "Blair Two" }])
      expect(row[:extendedProps][:background])
        .to eq("linear-gradient(to right, #ff0000 0.0%, #ff0000 50.0%, #bbb 50.0%, #bbb 100.0%); opacity: 0.8;")
    end

    it "gives a series its rule in Toronto time and its length in milliseconds" do
      event = create(:event, space: space, created_by: creator, start_time: Time.utc(2027, 5, 5, 13),
                             end_time: Time.utc(2027, 5, 5, 14, 30),
                             recurrence_rule: "DTSTART:20270505T130000Z\nRRULE:FREQ=WEEKLY;BYDAY=WE\nEXDATE:20270512T130000Z")
      expect(event.feed_row({})).to include(
        rrule: "DTSTART:20270505T090000\nRRULE:FREQ=WEEKLY;BYDAY=WE\nEXDATE:20270512T090000", duration: 5_400_000.0
      )
    end

    it "leaves the rule and length out of a one-off event" do
      event = build_event(recurrence_rule: "")
      expect(event.feed_row({}).keys).not_to include(:rrule, :duration)
    end
  end

  describe ".publish_range" do
    let(:editor) { create(:user, :admin) }
    let(:range) { Time.utc(2027, 4, 1)..Time.utc(2027, 4, 3) }

    def draft(**attrs)
      create(:event, :draft, space: space, created_by: creator, start_time: Time.utc(2027, 4, 2, 14),
                             end_time: Time.utc(2027, 4, 2, 15), **attrs)
    end

    it "publishes the space's drafts in the range as the editor, yielding each saved one, and returns the failures" do
      first = draft
      broken = draft(title: "Broken")
      broken.update_column(:recurrence_rule, "DTSTART:20270402T140000Z\nRRULE:FREQ=MINUTELY")
      outside = draft(start_time: Time.utc(2027, 4, 5, 14), end_time: Time.utc(2027, 4, 5, 15))
      elsewhere = create(:event, :draft, space: create(:space), created_by: creator, start_time: Time.utc(2027, 4, 2, 14),
                                         end_time: Time.utc(2027, 4, 2, 15))
      yielded = []

      published, failed = described_class.publish_range(space.id, range, by: editor) { |event| yielded << event }

      expect(published).to eq([first])
      expect(yielded).to eq([first])
      expect(failed).to eq([broken])
      expect(failed.first.errors[:recurrence_rule]).to be_present
      expect(first.reload).to have_attributes(draft: false, updated_by: editor)
      expect([broken, outside, elsewhere].map { |event| event.reload.draft }).to eq([true, true, true])
    end
  end

  describe "a stored repeat rule with an unreadable start" do
    let(:bad_rule) { "DTSTART;TZID=Nowhere/Land:20270401T100000\nRRULE:FREQ=DAILY" }

    it "still saves an unrelated change, but validates a changed rule" do
      event = build_event.tap(&:save!)
      event.update_column(:recurrence_rule, bad_rule)
      event.reload
      expect(event.update(title: "Renamed")).to be(true)
      expect(event.update(recurrence_rule: "#{bad_rule}\nEXDATE:20270402T140000Z")).to be(false)
      expect(event.errors[:recurrence_rule]).to eq([RecurrenceRuleValidator::UNPARSEABLE])
    end
  end
end

RSpec.describe Event, ".types_in", type: :model do
  it "lists the event types stored for a space, alphabetical, once each" do
    space = create(:space)
    create(:event, space: space, event_type: "shift")
    create(:event, space: space, event_type: "meeting")
    create(:event, space: space, event_type: "shift")
    create(:event, event_type: "other")

    expect(described_class.types_in(space.id)).to eq(%w[meeting shift])
  end
end
