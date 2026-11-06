require "rails_helper"
require Rails.root.join("db/migrate/20261104150000_backfill_volunteer_hour_dates_from_requests")

# Blank dates can only be inserted where the CHECK is missing, so the example drops it
# (DDL is transactional; the constraint is back after the rollback).
RSpec.describe BackfillVolunteerHourDatesFromRequests do
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user, :volunteer_with_volunteer_program) }
  let(:task) { create(:volunteer_task) }

  before { connection.remove_check_constraint(:volunteer_hours, name: "volunteer_hours_date_of_task_present_check") }

  def request_at(time, approval: true, user: self.user, task: self.task)
    req = create(:volunteer_task_request, user: user, volunteer_task: task, approval: approval)
    req.update_columns(created_at: time)
    req
  end

  def hour_at(time, date: nil, user: self.user, task: self.task)
    hour = create(:volunteer_hour, user: user, volunteer_task: task, approval: true, date_of_task: Time.current)
    hour.update_columns(created_at: time, date_of_task: date)
    hour
  end

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  let(:base) { Time.zone.parse("2026-05-01 12:00") }

  it "dates an hour with the created_at of its single approved request" do
    request_at(base - 3.days)
    hour = hour_at(base)

    migrate

    expect(hour.reload.date_of_task).to eq(base - 3.days)
  end

  it "uses the latest approved request created at or before the hour when there are several" do
    request_at(base - 10.days)
    request_at(base - 4.days)
    request_at(base + 1.day)
    hour = hour_at(base)

    migrate

    expect(hour.reload.date_of_task).to eq(base - 4.days)
  end

  it "uses a request created at the very moment of the hour" do
    request_at(base)
    hour = hour_at(base)

    migrate

    expect(hour.reload.date_of_task).to eq(base)
  end

  it "ignores requests that are not approved, and requests of another user or task" do
    request_at(base - 6.days)
    request_at(base - 1.day, approval: false)
    request_at(base - 2.days, approval: nil)
    request_at(base - 1.day, user: create(:user, :volunteer_with_volunteer_program))
    request_at(base - 1.day, task: create(:volunteer_task))
    hour = hour_at(base)

    migrate

    expect(hour.reload.date_of_task).to eq(base - 6.days)
  end

  it "does not touch an hour that already has a date" do
    request_at(base - 3.days)
    dated = hour_at(base, date: Time.zone.parse("2020-01-15 00:00"))

    migrate

    expect(dated.reload.date_of_task).to eq(Time.zone.parse("2020-01-15 00:00"))
    expect(connection.select_value("SELECT COUNT(*) FROM volunteer_hour_date_backfills").to_i).to eq(0)
  end

  it "leaves an hour without a matching request blank and reports the counts" do
    request_at(base - 3.days)
    matched = hour_at(base)
    orphan = hour_at(base, task: create(:volunteer_task))
    messages = []
    allow_any_instance_of(described_class).to receive(:say) { |_, text| messages << text }

    described_class.new.migrate(:up)

    expect(matched.reload.date_of_task).to be_present
    expect(orphan.reload.date_of_task).to be_nil
    expect(messages).to include("volunteer_hours: 1 dates filled from completion requests, 1 still blank")
  end

  it "leaves updated_at alone and is safe to run twice" do
    request_at(base - 3.days)
    hour = hour_at(base)
    hour.update_columns(updated_at: base)

    migrate
    migrate

    expect(hour.reload.updated_at).to eq(base)
    expect(hour.date_of_task).to eq(base - 3.days)
    expect(connection.select_value("SELECT COUNT(*) FROM volunteer_hour_date_backfills").to_i).to eq(1)
  end

  it "down blanks only the rows it filled and drops its table" do
    request_at(base - 3.days)
    filled = hour_at(base)
    kept = hour_at(base, date: Time.zone.parse("2020-01-15 00:00"))

    migrate
    expect(filled.reload.date_of_task).to eq(base - 3.days)
    migrate(:down)

    expect(filled.reload.date_of_task).to be_nil
    expect(kept.reload.date_of_task).to eq(Time.zone.parse("2020-01-15 00:00"))
    expect(connection.table_exists?("volunteer_hour_date_backfills")).to be(false)
  end

  it "records the date written to each hour it fills" do
    request_at(base - 3.days)
    filled = hour_at(base)
    migrate
    recorded = connection.select_rows("SELECT b.volunteer_hour_id, b.filled_value = h.date_of_task FROM volunteer_hour_date_backfills b JOIN volunteer_hours h ON h.id = b.volunteer_hour_id")
    expect(recorded).to eq([[filled.id, true]])
    expect(filled.reload.date_of_task).to eq(base - 3.days)
  end

  it "down leaves an hour whose date was edited since, refuses, and keeps the table" do
    request_at(base - 3.days)
    untouched = hour_at(base)
    edited = hour_at(base)
    migrate
    edited.update_columns(date_of_task: base + 1.day)

    expect { ApplicationRecord.transaction(requires_new: true) { migrate(:down) } }.to raise_error(/blanked 1 of 2.*nothing was changed/m)

    expect(edited.reload.date_of_task).to eq(base + 1.day)
    expect(untouched.reload.date_of_task).to eq(base - 3.days)
    expect(connection.select_value("SELECT COUNT(*) FROM volunteer_hour_date_backfills").to_i).to eq(2)
  end

  it "down refuses when a recorded hour is gone" do
    request_at(base - 3.days)
    hour = hour_at(base)
    migrate
    connection.execute("DELETE FROM volunteer_hours WHERE id = #{hour.id}")
    expect { ApplicationRecord.transaction(requires_new: true) { migrate(:down) } }.to raise_error(/blanked 0 of 1/)
  end
end
