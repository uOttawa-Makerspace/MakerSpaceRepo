# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffUnavailability, type: :model do
  let(:user) { create(:user, :staff) }
  let(:start_time) { Time.utc(2027, 3, 1, 15) }

  def build_one(**attrs)
    described_class.new({ user: user, start_time: start_time, end_time: start_time + 1.hour }.merge(attrs))
  end

  it { should belong_to(:user) }
  it { should validate_presence_of(:start_time) }
  it { should validate_presence_of(:end_time) }

  it "requires start before end (equal is invalid too)" do
    record = build_one(end_time: start_time)
    expect(record).not_to be_valid
    expect(record.errors[:start_time]).to eq(["must be before the end time"])
    expect(build_one(end_time: start_time - 1.minute)).not_to be_valid
  end

  it "requires BYDAY for a weekly rule" do
    record = build_one(recurrence_rule: "FREQ=WEEKLY;INTERVAL=1")
    expect(record).not_to be_valid
    expect(record.errors[:recurrence_rule]).to eq(["must include days of the week when using weekly frequency"])
    expect(build_one(recurrence_rule: "FREQ=WEEKLY;BYDAY=MO")).to be_valid
    expect(build_one(recurrence_rule: "FREQ=DAILY")).to be_valid
    expect(build_one(recurrence_rule: nil)).to be_valid
  end

  it "does not validate that the rule is parseable" do
    expect(build_one(recurrence_rule: "garbage")).to be_valid
  end

  it "stores instants and reads them back in the app zone (Eastern)" do
    record = build_one.tap(&:save!).reload
    expect(record.start_time.zone).to eq("EST")
    expect(record.start_time.utc).to eq(start_time)
  end
end
