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

      it "queues a move from the previous calendar when the space changed to another calendar" do
        old = create(:space, name: "MTC")
        event = create(:event, space: space, created_by: creator, google_event_id: "abc123")
        event.push_to_google_later(previous_space: old)
        expect(GoogleCalendar::EventMoveJob).to have_been_enqueued
          .with(event.id, "c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com")
        expect(GoogleCalendar::EventPushJob).not_to have_been_enqueued
      end

      it "queues a plain push when the previous space has the same calendar" do
        event = create(:event, space: space, created_by: creator)
        event.push_to_google_later(previous_space: create(:space))
        expect(GoogleCalendar::EventMoveJob).not_to have_been_enqueued
        expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(event.id)
      end

      it "queues nothing for a draft" do
        event = create(:event, :draft, space: space, created_by: creator, google_event_id: nil)
        event.push_to_google_later
        expect(GoogleCalendar::EventPushJob).not_to have_been_enqueued
        expect(event.reload.google_event_id).to be_nil
      end
    end

    describe ".remove_from_google_later" do
      it "queues the removal with the Google id and the space's calendar id" do
        described_class.remove_from_google_later("abc123", space)
        expect(GoogleCalendar::EventDeleteJob).to have_been_enqueued
          .with("abc123", "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com")
      end

      it "queues nothing without a Google id" do
        described_class.remove_from_google_later(nil, space)
        described_class.remove_from_google_later("", space)
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
end
