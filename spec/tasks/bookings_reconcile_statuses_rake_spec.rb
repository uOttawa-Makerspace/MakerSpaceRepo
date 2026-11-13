# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "bookings:reconcile_statuses", :booking_clock do
  let!(:pending) { create(:booking_status, :pending) }
  let!(:approved) { create(:booking_status, :approved) }
  let!(:declined) { create(:booking_status, :rejected) }

  let(:deployed_at) { 1.day.from_now }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DEPLOYED_AT").and_return(deployed_at.utc.iso8601)
  end

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("bookings:reconcile_statuses")
    Rake::Task["bookings:reconcile_statuses"].reenable
  end

  def run_task
    output = StringIO.new
    original = $stdout
    $stdout = output
    Rake::Task["bookings:reconcile_statuses"].invoke
    output.string
  ensure
    $stdout = original
  end

  # What code from before the column did: set the status on the old row only, so the row is newer.
  def write_old_row(booking, status)
    SubSpaceBookingStatus.find_by(sub_space_booking_id: booking.id)
                         .update_columns(booking_status_id: status.id, updated_at: booking.updated_at + 1.minute)
  end

  def old_row(booking)
    SubSpaceBookingStatus.find_by(sub_space_booking_id: booking.id)
  end

  it "copies the status row into an empty column and into a stale one, and prints what it changed" do
    empty = create(:sub_space_booking, :with_old_status_row)
    stale = create(:sub_space_booking, :with_old_status_row)
    write_old_row(empty, approved)
    empty.update_column(:booking_status_id, nil)
    write_old_row(stale, declined)

    output = run_task

    expect(empty.reload.booking_status).to eq(approved)
    expect(stale.reload.booking_status).to eq(declined)
    expect(output).to include("booking #{empty.id}: booking_status_id nil -> #{approved.id}")
    expect(output).to include("booking #{stale.id}: booking_status_id #{pending.id} -> #{declined.id}")
    expect(output).to include("2 booking(s) changed")
  end

  it "never changes the old status rows or a booking that already agrees" do
    agreeing = create(:sub_space_booking, :with_old_status_row)
    agreeing.change_status!(approved)
    write_old_row(agreeing, approved)
    rows_before = SubSpaceBookingStatus.order(:id).pluck(:id, :booking_status_id, :sub_space_booking_id, :updated_at)

    expect(run_task).to include("0 booking(s) changed")

    expect(SubSpaceBookingStatus.order(:id).pluck(:id, :booking_status_id, :sub_space_booking_id, :updated_at)).to eq(rows_before)
    expect(agreeing.reload.booking_status).to eq(approved)
  end

  it "is safe to run twice" do
    stale = create(:sub_space_booking, :with_old_status_row)
    write_old_row(stale, approved)
    run_task
    Rake::Task["bookings:reconcile_statuses"].reenable

    expect(run_task).to include("0 booking(s) changed")
    expect(stale.reload.booking_status).to eq(approved)
  end

  it "copies an old row onto a booking with no status even when the booking is newer than the row" do
    booking = create(:sub_space_booking, :with_old_status_row)
    old_row(booking).update_columns(booking_status_id: approved.id, updated_at: booking.updated_at - 1.hour)
    booking.update_column(:booking_status_id, nil)

    run_task

    expect(booking.reload.booking_status).to eq(approved)
  end

  it "copies an old row over a booking edited after the old approve, both before the deploy" do
    booking = create(:sub_space_booking, :with_old_status_row)
    old_row(booking).update_columns(booking_status_id: approved.id, updated_at: booking.updated_at + 1.minute)
    booking.update_column(:updated_at, booking.updated_at + 2.minutes)

    run_task

    expect(booking.reload.booking_status).to eq(approved)
  end

  context "when the new release changed a status after the deploy" do
    let(:deployed_at) { Time.current }

    it "skips the booking and lists it, and still copies the others" do
      changed = create(:sub_space_booking, :with_old_status_row)
      stale = create(:sub_space_booking, :with_old_status_row)
      changed.update_columns(booking_status_id: declined.id, updated_at: deployed_at + 1.minute)
      write_old_row(stale, approved)
      stale.update_column(:updated_at, deployed_at - 1.minute)

      output = run_task

      expect(changed.reload.booking_status).to eq(declined)
      expect(stale.reload.booking_status).to eq(approved)
      expect(output).to include("1 booking(s) changed")
      expect(output).to include("1 booking(s) skipped").and include("ids: #{changed.id}")
      expect(SubSpaceBooking.connection.select_value("SELECT count(*) FROM booking_status_reconciliations WHERE sub_space_booking_id = #{changed.id}")).to eq(0)
    end

    it "does not undo a booking approved by the new release" do
      booking = create(:sub_space_booking, :with_old_status_row)
      travel_to(deployed_at + 5.minutes) { booking.approve_if_pending!(by: booking.user) }

      run_task

      expect(booking.reload).to be_approved
      expect(old_row(booking).booking_status).to eq(pending)
    end
  end

  it "refuses to run without a usable DEPLOYED_AT, and changes nothing" do
    booking = create(:sub_space_booking, :with_old_status_row)
    write_old_row(booking, approved)
    [nil, "", "yesterday", "2026-11-15T14:30:00"].each do |value|
      allow(ENV).to receive(:[]).with("DEPLOYED_AT").and_return(value)
      Rake::Task["bookings:reconcile_statuses"].reenable

      expect { expect { run_task }.to output(/DEPLOYED_AT/).to_stderr }.to raise_error(SystemExit)
    end

    expect(booking.reload.booking_status).to eq(pending)
  end

  it "leaves a booking with no matching status row alone and lists it" do
    orphan = create(:sub_space_booking, :with_old_status_row)
    orphan.update_column(:booking_status_id, nil)
    SubSpaceBooking.where(id: orphan.id).update_all(sub_space_booking_status_id: nil)

    output = run_task

    expect(orphan.reload.booking_status_id).to be_nil
    expect(output).to include("ids: #{orphan.id}")
  end
end

RSpec.describe "bookings:restore_reconciled_statuses", :booking_clock do
  let!(:pending) { create(:booking_status, :pending) }
  let!(:approved) { create(:booking_status, :approved) }
  let!(:declined) { create(:booking_status, :rejected) }

  # What code from before the column did: set the status on the old row only, so the row is newer.
  def write_old_row(booking, status)
    SubSpaceBookingStatus.find_by(sub_space_booking_id: booking.id)
                         .update_columns(booking_status_id: status.id, updated_at: booking.updated_at + 1.minute)
  end

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("bookings:reconcile_statuses")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DEPLOYED_AT").and_return(1.day.from_now.utc.iso8601)
  end

  def run(name)
    Rake::Task[name].reenable
    output = StringIO.new
    original = $stdout
    $stdout = output
    Rake::Task[name].invoke
    output.string
  ensure
    $stdout = original
  end

  def records
    SubSpaceBooking.connection.select_rows(
      "SELECT sub_space_booking_id, was_booking_status_id, now_booking_status_id FROM booking_status_reconciliations ORDER BY id"
    )
  end

  let!(:empty) { create(:sub_space_booking, :with_old_status_row) }
  let!(:stale) { create(:sub_space_booking, :with_old_status_row) }

  before do
    write_old_row(empty, approved)
    empty.update_column(:booking_status_id, nil)
    write_old_row(stale, declined)
  end

  it "reconcile records one row per change in the same run, and none on a second run" do
    run("bookings:reconcile_statuses")

    expect(records).to eq([[empty.id, nil, approved.id], [stale.id, pending.id, declined.id]])
    run("bookings:reconcile_statuses")
    expect(records.size).to eq(2)
  end

  it "records nothing for a booking that already agrees" do
    agreeing = create(:sub_space_booking, :with_old_status_row)
    agreeing.change_status!(approved)
    write_old_row(agreeing, approved)

    run("bookings:reconcile_statuses")

    expect(records.map(&:first)).to eq([empty.id, stale.id])
    expect(records.map(&:first)).not_to include(agreeing.id)
  end

  it "puts the column back exactly, keeps the record and the old status rows, and can run twice" do
    column_before = SubSpaceBooking.order(:id).pluck(:id, :booking_status_id)
    rows_before = SubSpaceBookingStatus.order(:id).pluck(:id, :booking_status_id, :sub_space_booking_id)
    run("bookings:reconcile_statuses")

    expect(run("bookings:restore_reconciled_statuses")).to include("2 booking(s) restored")

    expect(SubSpaceBooking.order(:id).pluck(:id, :booking_status_id)).to eq(column_before)
    expect(SubSpaceBookingStatus.order(:id).pluck(:id, :booking_status_id, :sub_space_booking_id)).to eq(rows_before)
    expect(records.size).to eq(2)
    output = run("bookings:restore_reconciled_statuses")
    expect(output).to include("0 booking(s) restored")
    expect(output).not_to include("left alone")
  end

  it "leaves a booking alone, and lists it, when its column was changed after the reconcile" do
    run("bookings:reconcile_statuses")
    stale.change_status!(pending)
    stale.update_column(:booking_status_id, approved.id)

    output = run("bookings:restore_reconciled_statuses")

    expect(output).to include("1 booking(s) restored").and include("booking ids: #{stale.id}")
    expect(stale.reload.booking_status).to eq(approved)
    expect(empty.reload.booking_status_id).to be_nil
  end

  it "marks each record restored in the restore itself, prints it, and a second restore does nothing" do
    run("bookings:reconcile_statuses")

    output = run("bookings:restore_reconciled_statuses")

    expect(output).to include("booking #{empty.id}: booking_status_id #{approved.id} -> nil")
    expect(output).to include("booking #{stale.id}: booking_status_id #{declined.id} -> #{pending.id}")
    expect(SubSpaceBooking.connection.select_value("SELECT COUNT(*) FROM booking_status_reconciliations WHERE restored_at IS NULL").to_i).to eq(0)
    expect(run("bookings:restore_reconciled_statuses")).to include("0 booking(s) restored")
  end

  it "restores a booking reconciled twice to its first value, newest change first" do
    run("bookings:reconcile_statuses")
    write_old_row(stale, approved)
    run("bookings:reconcile_statuses")
    expect(records.select { |r| r.first == stale.id }).to eq([[stale.id, pending.id, declined.id], [stale.id, declined.id, approved.id]])

    expect(run("bookings:restore_reconciled_statuses")).to include("3 booking(s) restored")

    expect(stale.reload.booking_status).to eq(pending)
    expect(empty.reload.booking_status_id).to be_nil
  end

  it "does not undo an older change of a booking once a newer one was left alone" do
    run("bookings:reconcile_statuses")
    write_old_row(stale, approved)
    run("bookings:reconcile_statuses")
    stale.change_status!(declined)

    output = run("bookings:restore_reconciled_statuses")

    expect(stale.reload.booking_status).to eq(declined)
    expect(output).to include("1 booking(s) restored")
    expect(output).to include("1 record(s) left alone, the column no longer holds the recorded value (booking ids: #{stale.id})")
    expect(output).to include("1 record(s) left alone, a newer change of the booking was left alone (booking ids: #{stale.id})")
    unrestored = SubSpaceBooking.connection.select_values("SELECT sub_space_booking_id FROM booking_status_reconciliations WHERE restored_at IS NULL")
    expect(unrestored).to eq([stale.id, stale.id])
  end

  it "keeps the record when a booking is deleted, and lists it as gone on restore" do
    run("bookings:reconcile_statuses")
    empty.destroy_with_status!

    expect(records.map(&:first)).to eq([empty.id, stale.id])
    output = run("bookings:restore_reconciled_statuses")
    expect(output).to include("1 booking(s) restored").and include("booking gone (booking ids: #{empty.id})")
  end
end
