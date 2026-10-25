# frozen_string_literal: true

require "rails_helper"

# ChatMessage: scopes, the unread counter, timestamp formatting across
# midnight and the notification hook (throttle boundary and Draft skip) by
# delivered outcome.

RSpec.describe ChatMessage, type: :model do
  include JobOrderSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:order) { make_job_order!(owner: owner, status_key: :user_approval) }

  before do
    seed_job_statuses!
    ActionMailer::Base.deliveries.clear
  end

  describe "validations" do
    it "requires a message" do
      message = described_class.new(job_order: order, sender: owner, message: "")
      expect(message).not_to be_valid
      expect(message.errors[:message]).to eq(["This field is required."])
    end

    it "requires a job order and a sender on a persisted record" do
      message = described_class.new(message: "hi")
      expect(message).not_to be_valid
      expect(message.errors.attribute_names).to include(:job_order, :sender)
    end
  end

  describe ".unread" do
    it "returns unread messages from other senders only" do
      theirs = described_class.create!(job_order: order, sender: staff, message: "from staff")
      described_class.create!(job_order: order, sender: owner, message: "mine")
      read = described_class.create!(job_order: order, sender: staff, message: "read", is_read: true)

      expect(described_class.unread(owner)).to contain_exactly(theirs)
      expect(described_class.unread(owner)).not_to include(read)
    end

    it "excludes messages with a NULL sender (SQL != NULL is never true)" do
      orphan = described_class.create!(job_order: order, sender: User.new, message: "guest")
      expect(orphan.reload.sender_id).to be_nil
      expect(described_class.unread(owner)).to be_empty
    end
  end

  describe ".count_unread_by_admin" do
    it "counts the newest consecutive messages written by the order's owner" do
      travel_to(Time.utc(2027, 1, 1, 12)) { described_class.create!(job_order: order, sender: owner, message: "old owner") }
      travel_to(Time.utc(2027, 1, 1, 13)) { described_class.create!(job_order: order, sender: staff, message: "staff reply") }
      travel_to(Time.utc(2027, 1, 1, 14)) { described_class.create!(job_order: order, sender: owner, message: "owner 1") }
      travel_to(Time.utc(2027, 1, 1, 15)) { described_class.create!(job_order: order, sender: owner, message: "owner 2") }

      expect(described_class.count_unread_by_admin(order)).to eq(2)
    end

    it "is 0 when staff wrote last and for an empty thread" do
      expect(described_class.count_unread_by_admin(order)).to eq(0)
      described_class.create!(job_order: order, sender: staff, message: "last word")
      expect(described_class.count_unread_by_admin(order)).to eq(0)
    end
  end

  describe "#timestamp" do
    let(:message) do
      travel_to(Time.zone.local(2027, 3, 10, 23, 30)) do
        described_class.create!(job_order: order, sender: owner, message: "late")
      end
    end

    it "shows only the time of day on the same day" do
      message
      travel_to(Time.zone.local(2027, 3, 10, 23, 59)) do
        expect(message.timestamp).to eq("11:30 PM")
      end
    end

    it "switches to the short date format after midnight" do
      message
      travel_to(Time.zone.local(2027, 3, 11, 0, 1)) do
        expect(message.timestamp).to eq("Mar 10, 11:30 PM")
      end
    end
  end

  describe "notification after_save" do
    def create_at(time, sender, text)
      travel_to(time) do
        perform_enqueued_jobs { described_class.create!(job_order: order, sender: sender, message: text) }
      end
    end

    before do
      # a prior owner message makes the owner a recipient of staff messages
      travel_to(Time.utc(2027, 1, 1, 9)) { described_class.create!(job_order: order, sender: owner, message: "first") }
      ActionMailer::Base.deliveries.clear
    end

    it "throttles a sender's second message through exactly one hour (>= boundary) and mails again after it" do
      start = Time.utc(2027, 1, 1, 10)
      create_at(start, staff, "m1")
      expect(ActionMailer::Base.deliveries.size).to eq(1)

      create_at(start + 1.hour, staff, "m2") # exactly 1h later: still inside the window
      expect(ActionMailer::Base.deliveries.size).to eq(1)

      create_at(start + 1.hour + 1.second, staff, "m3") # m1 is now older than 1h, m2 is not -> still throttled
      expect(ActionMailer::Base.deliveries.size).to eq(1)

      create_at(start + 2.hours + 2.seconds, staff, "m4") # nothing within the last hour
      expect(ActionMailer::Base.deliveries.size).to eq(2)
      expect(ActionMailer::Base.deliveries.map(&:to)).to all(eq([owner.email]))
    end

    it "sends nothing while the order is still a Draft" do
      draft = make_job_order!(owner: owner, status_key: :draft)
      perform_enqueued_jobs do
        described_class.create!(job_order: draft, sender: owner, message: "first")
        described_class.create!(job_order: draft, sender: staff, message: "reply")
      end
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
