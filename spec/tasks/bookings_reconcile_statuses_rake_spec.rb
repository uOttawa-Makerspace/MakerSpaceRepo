# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "bookings:reconcile_statuses", :booking_clock do
  let!(:pending) { create(:booking_status, :pending) }
  let!(:approved) { create(:booking_status, :approved) }
  let!(:declined) { create(:booking_status, :rejected) }

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

  def old_row(booking)
    SubSpaceBookingStatus.find_by(sub_space_booking_id: booking.id)
  end

  it "copies the status row into an empty column and into a stale one, and prints what it changed" do
    empty = create(:sub_space_booking)
    stale = create(:sub_space_booking)
    old_row(empty).update_columns(booking_status_id: approved.id)
    empty.update_column(:booking_status_id, nil)
    old_row(stale).update_columns(booking_status_id: declined.id)

    output = run_task

    expect(empty.reload.booking_status).to eq(approved)
    expect(stale.reload.booking_status).to eq(declined)
    expect(output).to include("booking #{empty.id}: booking_status_id nil -> #{approved.id}")
    expect(output).to include("booking #{stale.id}: booking_status_id #{pending.id} -> #{declined.id}")
    expect(output).to include("2 booking(s) changed")
  end

  it "never changes the old status rows or a booking that already agrees" do
    agreeing = create(:sub_space_booking)
    agreeing.change_status!(approved)
    rows_before = SubSpaceBookingStatus.order(:id).pluck(:id, :booking_status_id, :sub_space_booking_id, :updated_at)

    expect(run_task).to include("0 booking(s) changed")

    expect(SubSpaceBookingStatus.order(:id).pluck(:id, :booking_status_id, :sub_space_booking_id, :updated_at)).to eq(rows_before)
    expect(agreeing.reload.booking_status).to eq(approved)
  end

  it "is safe to run twice" do
    stale = create(:sub_space_booking)
    old_row(stale).update_columns(booking_status_id: approved.id)
    run_task
    Rake::Task["bookings:reconcile_statuses"].reenable

    expect(run_task).to include("0 booking(s) changed")
    expect(stale.reload.booking_status).to eq(approved)
  end

  it "leaves a booking with no matching status row alone and lists it" do
    orphan = create(:sub_space_booking)
    orphan.update_column(:booking_status_id, nil)
    SubSpaceBooking.where(id: orphan.id).update_all(sub_space_booking_status_id: nil)

    output = run_task

    expect(orphan.reload.booking_status_id).to be_nil
    expect(output).to include("ids: #{orphan.id}")
  end
end
