# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261109120000_store_repeat_rules_in_toronto_time")

# The stored repeat rules move from a UTC start line to a Toronto one. The
# rewrite is recorded row by row, down restores the exact old text, and both
# forms must read the same (RecurrenceRule and the server expansion).
RSpec.describe StoreRepeatRulesInTorontoTime do
  let(:connection) { ActiveRecord::Base.connection }
  let(:cases) { JSON.parse(Rails.root.join("spec/fixtures/calendar_dst_cases.json").read)["storedRules"] }
  let(:space) { create(:space) }
  let(:staff) { create(:user, :staff) }

  # The schema already has the record table; the migration creates it.
  before { connection.drop_table(:recurrence_rule_rewrites) }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def stored(record) = connection.select_value("SELECT recurrence_rule FROM #{record.class.table_name} WHERE id = #{record.id}")

  def event_with(rule, start = Time.utc(2027, 3, 10, 15))
    create(:event, space: space, start_time: start, end_time: start + 1.hour, recurrence_rule: rule)
  end

  def unavailability_with(rule, start = Time.utc(2027, 3, 10, 15))
    create(:staff_unavailability, user: staff, start_time: start, end_time: start + 1.hour, recurrence_rule: rule)
  end

  def snapshot
    %w[events staff_unavailabilities].index_with do |table|
      connection.select_rows("SELECT id, recurrence_rule, updated_at FROM #{table} ORDER BY id")
    end
  end

  it "rewrites each rule of the table to its Toronto form, events and unavailabilities alike" do
    records = cases.flat_map do |c|
      start = Time.iso8601(c["start"])
      [event_with(c["utc"], start), unavailability_with(c["utc"], start)]
    end
    migrate(:up)
    expect(records.map { |r| stored(r) }).to eq(cases.flat_map { |c| [c["toronto"], c["toronto"]] })
  end

  it "keeps the meaning of every rewritten rule: the same start and the same occurrences" do
    records = cases.map { |c| event_with(c["utc"], Time.iso8601(c["start"])) }
    before_texts = records.map { |r| stored(r) }
    migrate(:up)
    records.zip(before_texts).each do |record, old_text|
      new_text = stored(record)
      old_rule = RecurrenceRule.new(old_text, nil)
      new_rule = RecurrenceRule.new(new_text, nil)
      expect(new_rule.starts_at).to eq(old_rule.starts_at)
      expand = ->(text, start) { RecurrenceExpansion.occurrences(text, start, start, start + 1.year, 500).occurrences }
      expect(expand.call(new_text, new_rule.starts_at)).to eq(expand.call(old_text, old_rule.starts_at))
    end
  end

  it "records the table, the row and the old and new text of each rewrite" do
    event = event_with("DTSTART:20270310T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=WE\nEXDATE:20270317T140000Z")
    migrate(:up)
    expect(connection.select_rows("SELECT table_name, record_id, old_rule, new_rule, migration_version FROM recurrence_rule_rewrites"))
      .to eq([["events", event.id, "DTSTART:20270310T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=WE\nEXDATE:20270317T140000Z",
               "DTSTART;TZID=America/Toronto:20270310T100000\nRRULE:FREQ=WEEKLY;BYDAY=WE\nEXDATE:20270317T140000Z",
               "20261109120000"]])
  end

  it "leaves updated_at and every other rule as they are" do
    blank = create(:event, space: space, recurrence_rule: nil)
    no_start = event_with("RRULE:FREQ=DAILY;COUNT=2")
    already = event_with("DTSTART;TZID=America/Toronto:20270310T100000\nRRULE:FREQ=DAILY;COUNT=2")
    rewritten = event_with("DTSTART:20270310T150000Z\nRRULE:FREQ=DAILY;COUNT=2")
    before_snapshot = snapshot
    migrate(:up)
    after_snapshot = snapshot
    changed = after_snapshot["events"] - before_snapshot["events"]
    expect(changed.map(&:first)).to eq([rewritten.id])
    expect(changed.first.last).to eq(before_snapshot["events"].find { |row| row.first == rewritten.id }.last)
    expect([blank, no_start, already].map { |r| stored(r) })
      .to eq([nil, "RRULE:FREQ=DAILY;COUNT=2", "DTSTART;TZID=America/Toronto:20270310T100000\nRRULE:FREQ=DAILY;COUNT=2"])
  end

  it "keeps a rule whose start is the second 1:30 of the night the clocks go back, which Toronto time cannot name" do
    # 06:30 UTC on 2027-11-07 is 1:30 standard time, after the first 1:30 daylight time
    second = "DTSTART:20271107T063000Z\nRRULE:FREQ=DAILY;COUNT=3"
    event = event_with(second, Time.utc(2027, 11, 7, 6, 30))
    migrate(:up)
    expect(stored(event)).to eq(second)
    expect(connection.select_value("SELECT count(*) FROM recurrence_rule_rewrites")).to eq(0)
  end

  it "keeps a rule it cannot read, and one with two start lines" do
    # stored before the rules were validated
    two_starts = event_with("RRULE:FREQ=DAILY")
    two_starts.update_column(:recurrence_rule, "DTSTART:20270310T150000Z\nDTSTART:20270311T150000Z\nRRULE:FREQ=DAILY")
    unreadable = event_with("RRULE:FREQ=DAILY")
    unreadable.update_column(:recurrence_rule, "DTSTART:20270310T150000Z\nRRULE:FREQ=FORTNIGHTLY")
    migrate(:up)
    expect(stored(two_starts)).to eq("DTSTART:20270310T150000Z\nDTSTART:20270311T150000Z\nRRULE:FREQ=DAILY")
    expect(stored(unreadable)).to eq("DTSTART:20270310T150000Z\nRRULE:FREQ=FORTNIGHTLY")
  end

  it "restores the exact old text and drops the record table on down" do
    cases.each { |c| event_with(c["utc"], Time.iso8601(c["start"])) }
    unavailability_with("DTSTART:20270310T150000Z\r\nRRULE:FREQ=DAILY;COUNT=2")
    before_snapshot = snapshot
    migrate(:up)
    expect(snapshot).not_to eq(before_snapshot)
    migrate(:down)
    expect(snapshot).to eq(before_snapshot)
    expect(connection.table_exists?(:recurrence_rule_rewrites)).to be(false)
  end

  it "skips a rewritten row deleted since on down" do
    event = event_with("DTSTART:20270310T150000Z\nRRULE:FREQ=DAILY;COUNT=2")
    kept = unavailability_with("DTSTART:20270310T150000Z\nRRULE:FREQ=DAILY;COUNT=2")
    migrate(:up)
    event.destroy!
    migrate(:down)
    expect(stored(kept)).to eq("DTSTART:20270310T150000Z\nRRULE:FREQ=DAILY;COUNT=2")
  end

  it "refuses down, changing nothing, while a rewritten rule has been edited since, and names how many" do
    edited = event_with("DTSTART:20270310T150000Z\nRRULE:FREQ=DAILY;COUNT=2")
    untouched = unavailability_with("DTSTART:20270310T150000Z\nRRULE:FREQ=DAILY;COUNT=2")
    migrate(:up)
    edited.update_column(:recurrence_rule, "DTSTART;TZID=America/Toronto:20270310T110000\nRRULE:FREQ=DAILY;COUNT=2")
    expect { migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /^1 rewritten repeat rule\(s\) were changed/)
    expect(stored(untouched)).to eq("DTSTART;TZID=America/Toronto:20270310T100000\nRRULE:FREQ=DAILY;COUNT=2")
    expect(connection.select_value("SELECT count(*) FROM recurrence_rule_rewrites")).to eq(2)
  end
end
