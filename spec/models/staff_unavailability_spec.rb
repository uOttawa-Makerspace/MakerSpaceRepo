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
    record = build_one(recurrence_rule: "RRULE:FREQ=WEEKLY;INTERVAL=1")
    expect(record).not_to be_valid
    expect(record.errors[:recurrence_rule]).to eq(["must include days of the week when using weekly frequency"])
    expect(build_one(recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=MO")).to be_valid
    expect(build_one(recurrence_rule: "RRULE:FREQ=DAILY")).to be_valid
    expect(build_one(recurrence_rule: nil)).to be_valid
  end

  it "refuses an unparseable or sub-daily rule" do
    expect(build_one(recurrence_rule: "garbage")).not_to be_valid
    record = build_one(recurrence_rule: "RRULE:FREQ=MINUTELY")
    expect(record).not_to be_valid
    expect(record.errors[:recurrence_rule].first).to start_with("must repeat daily")
  end

  it "stores instants and reads them back in the app zone (Eastern)" do
    record = build_one.tap(&:save!).reload
    expect(record.start_time.zone).to eq("EST")
    expect(record.start_time.utc).to eq(start_time)
  end

  it "saves an unrelated change to a stored rule with an unreadable start, but validates a changed rule" do
    bad_rule = "DTSTART;TZID=Nowhere/Land:20270301T100000\nRRULE:FREQ=DAILY"
    record = build_one.tap(&:save!)
    record.update_column(:recurrence_rule, bad_rule)
    record.reload
    expect(record.update(end_time: start_time + 2.hours)).to be(true)
    expect(record.update(recurrence_rule: "#{bad_rule};COUNT=2")).to be(false)
    expect(record.errors[:recurrence_rule]).to eq([RecurrenceRuleValidator::UNPARSEABLE])
  end
end

RSpec.describe StaffUnavailability, "#feed_rows", type: :model do
  let(:zone) { RecurrenceRule::ZONE }
  let(:week) { CalendarWindow.new(zone.local(2027, 3, 14), zone.local(2027, 3, 21)) }

  let(:row) { { title: "Away", className: "unavailability", extendedProps: { name: "Ann" } } }

  it "is the row of a one-off in the window, with its Toronto offset and record id" do
    unavailability = create(:staff_unavailability, title: "Doctor", description: "Away",
                                                   start_time: zone.local(2027, 3, 15, 9), end_time: zone.local(2027, 3, 15, 11))

    expect(unavailability.feed_rows(week, row)).to eq([{
      id: unavailability.id, title: "Away", start: "2027-03-15T09:00:00-04:00", end: "2027-03-15T11:00:00-04:00",
      allDay: false, className: "unavailability",
      extendedProps: { name: "Ann", eventType: "unavailability", userId: unavailability.user_id, recordId: unavailability.id,
                       isAdminCreated: false, series: nil, occurrenceStart: "2027-03-15T13:00:00Z" }
    }])
  end

  it "is each occurrence of a series in the window, with what the dialogs show of its repeat" do
    unavailability = create(:staff_unavailability, start_time: zone.local(2027, 1, 4, 9), end_time: zone.local(2027, 1, 4, 10),
                                                   recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=MO,WE")
    rows = unavailability.feed_rows(week, row)

    expect(rows.map { |row| row[:start] }).to eq(%w[2027-03-15T09:00:00-04:00 2027-03-17T09:00:00-04:00])
    expect(rows.map { |row| row[:id] }).to eq(["#{unavailability.id}@#{Time.utc(2027, 3, 15, 13).to_i}", "#{unavailability.id}@#{Time.utc(2027, 3, 17, 13).to_i}"])
    expect(rows.first[:extendedProps]).to include(recordId: unavailability.id, series: { frequency: "WEEKLY", weekdays: %w[MO WE], until: nil })
  end
end
