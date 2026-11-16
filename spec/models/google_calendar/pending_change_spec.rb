# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::PendingChange do
  let(:calendar_id) { "c_cal@group.calendar.google.com" }

  describe ".ask_push" do
    it "records one row per event however many times it is asked" do
      expect { 3.times { described_class.ask_push(7) } }.to change(described_class, :count).by(1)
      expect(described_class.last).to have_attributes(action: "push", event_id: 7, attempts: 0)
    end

    it "resets the resend count" do
      change = described_class.ask_push(7)
      change.update_columns(attempts: 3)
      expect(described_class.ask_push(7).attempts).to eq(0)
    end
  end

  describe ".ask_shadow_push" do
    it "records one row per shadowing shift however many times it is asked" do
      shift = create(:shadowing_hour)
      expect { 3.times { described_class.ask_shadow_push(shift.id) } }.to change(described_class, :count).by(1)
      expect(described_class.last).to have_attributes(action: "shadow_push", event_id: nil, shadowing_hour_id: shift.id, attempts: 0)
    end

    it "keeps one row for each shift" do
      expect { 2.times { described_class.ask_shadow_push(create(:shadowing_hour).id) } }.to change(described_class, :count).by(2)
    end

    it "is removed with the shift it belongs to" do
      shift = create(:shadowing_hour)
      described_class.ask_shadow_push(shift.id)
      expect { shift.destroy! }.to change(described_class, :count).by(-1)
    end

    it "is refused by the database without a shift, or with an event" do
      expect { described_class.create!(action: "shadow_push", event_id: 7) }.to raise_error(ActiveRecord::StatementInvalid)
      expect { described_class.create!(action: "push", event_id: 7, shadowing_hour_id: create(:shadowing_hour).id) }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe ".ask_removal" do
    it "records one row per Google copy of the event" do
      expect do
        described_class.ask_removal(7, "aaa", calendar_id)
        described_class.ask_removal(7, "aaa", calendar_id)
        described_class.ask_removal(7, "bbb", calendar_id)
      end.to change(described_class, :count).by(2)
    end
  end

  describe ".settle" do
    it "deletes the row asked for before the job started" do
      described_class.ask_push(7)
      expect { described_class.settle("push", 7, Time.current) }.to change(described_class, :count).by(-1)
    end

    it "keeps a row asked for again after the job started" do
      started_at = 1.minute.ago
      described_class.ask_push(7)
      expect { described_class.settle("push", 7, started_at) }.not_to change(described_class, :count)
    end

    it "settles only the removal of the copy it names" do
      described_class.ask_removal(7, "aaa", calendar_id)
      described_class.ask_removal(7, "bbb", calendar_id)
      described_class.settle("remove", 7, Time.current, google_event_id: "aaa")
      expect(described_class.pluck(:google_event_id)).to eq(["bbb"])
    end

    it "leaves the push of the same event alone when a removal is settled" do
      described_class.ask_push(7)
      described_class.ask_removal(7, "aaa", calendar_id)
      described_class.settle("remove", 7, Time.current, google_event_id: "aaa")
      expect(described_class.pluck(:action)).to eq(["push"])
    end
  end

  describe ".settle_shadow_push" do
    it "deletes the row asked for before the job started, and keeps one asked for again after it" do
      shift = create(:shadowing_hour)
      started_at = Time.current
      described_class.ask_shadow_push(shift.id)
      expect { described_class.settle_shadow_push(shift.id, started_at - 1.minute) }.not_to change(described_class, :count)
      expect { described_class.settle_shadow_push(shift.id, started_at + 1.minute) }.to change(described_class, :count).by(-1)
    end

    it "leaves an event's push alone" do
      described_class.ask_push(7)
      expect { described_class.settle_shadow_push(7, Time.current) }.not_to change(described_class, :count)
    end
  end

  describe "#enqueue" do
    it "queues the shadowing push job for a shadowing shift" do
      shift = create(:shadowing_hour)
      expect { described_class.ask_shadow_push(shift.id).enqueue }.to have_enqueued_job(GoogleCalendar::ShadowingPushJob).with(shift.id)
    end

    it "queues the push job for a push" do
      expect { described_class.ask_push(7).enqueue }.to have_enqueued_job(GoogleCalendar::EventPushJob).with(7)
    end

    it "queues the delete job for a removal" do
      expect { described_class.ask_removal(7, "aaa", calendar_id).enqueue }
        .to have_enqueued_job(GoogleCalendar::EventDeleteJob).with("aaa", calendar_id, 7)
    end

    [ActiveRecord::ConnectionNotEstablished, ActiveJob::EnqueueError].each do |error|
      it "reports #{error} and keeps the row when the queue cannot take the job" do
        allow(GoogleCalendar::EventPushJob).to receive(:perform_later).and_raise(error, "queue down")
        change = described_class.ask_push(7)
        expect(Rails.error).to receive(:report).with(instance_of(error), hash_including(handled: true))
        expect(change.enqueue).to be(false)
        expect(described_class.exists?(change.id)).to be(true)
      end
    end
  end

  describe ".resend_due" do
    it "queues a shadowing shift's event that waited long enough, counting the try" do
      shift = create(:shadowing_hour)
      described_class.ask_shadow_push(shift.id).update_columns(updated_at: 20.minutes.ago)
      expect { expect(described_class.resend_due).to eq(1) }.to have_enqueued_job(GoogleCalendar::ShadowingPushJob).with(shift.id).exactly(:once)
      expect(described_class.last.attempts).to eq(1)
    end

    it "queues the changes that waited long enough and counts the try" do
      due = described_class.ask_push(7)
      due.update_columns(updated_at: 20.minutes.ago)
      fresh = described_class.ask_push(8)
      expect { expect(described_class.resend_due).to eq(1) }.to have_enqueued_job(GoogleCalendar::EventPushJob).with(7).exactly(:once)
      expect(due.reload.attempts).to eq(1)
      expect(fresh.reload.attempts).to eq(0)
    end

    it "reports the change on its last try and stops queuing it after that" do
      change = described_class.ask_push(7)
      change.update_columns(updated_at: 20.minutes.ago, attempts: described_class::MAX_RESENDS - 1)
      expect(Rails.error).to receive(:report).with(instance_of(RuntimeError), hash_including(context: hash_including(event_id: 7))).once
      expect { described_class.resend_due }.to have_enqueued_job(GoogleCalendar::EventPushJob)
      expect { expect(described_class.resend_due).to eq(0) }.not_to have_enqueued_job(GoogleCalendar::EventPushJob)
    end

    it "lets an overlapping run claim nothing: each change is queued and counted once" do
      change = described_class.ask_push(7)
      change.update_columns(updated_at: 20.minutes.ago)
      expect { expect(described_class.resend_due).to eq(1) }.to have_enqueued_job(GoogleCalendar::EventPushJob).once
      expect { expect(described_class.resend_due).to eq(0) }.not_to have_enqueued_job(GoogleCalendar::EventPushJob)
      expect(change.reload.attempts).to eq(1)
    end

    it "keeps counting when the queue is down" do
      allow(GoogleCalendar::EventPushJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionNotEstablished)
      change = described_class.ask_push(7)
      change.update_columns(updated_at: 20.minutes.ago)
      expect(described_class.resend_due).to eq(0)
      expect(change.reload.attempts).to eq(1)
    end
  end
end
