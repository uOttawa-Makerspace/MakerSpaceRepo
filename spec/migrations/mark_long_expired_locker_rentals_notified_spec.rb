# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261104120000_mark_long_expired_locker_rentals_notified")

RSpec.describe MarkLongExpiredLockerRentalsNotified do
  let(:marker) { described_class::MARKER }

  def rental(owned_until:, **attrs)
    create(:locker_rental, :active, owned_until: owned_until, **attrs)
  end

  def run(direction) = ActiveRecord::Migration.suppress_messages { described_class.new.public_send(direction) }

  it "marks active rentals that expired more than 14 days ago and were never notified, without mailing" do
    old = rental(owned_until: 15.days.ago)
    older_with_notes = rental(owned_until: 200.days.ago)
    older_with_notes.update_columns(staff_notes: "call back")
    ActionMailer::Base.deliveries.clear

    run(:up)

    expect(old.reload.notified_of_cancellation_at).to be_within(1.minute).of(Time.current)
    expect(old.staff_notes).to eq(marker)
    expect(older_with_notes.reload.staff_notes).to eq("call back\n#{marker}")
    expect(old.contacted_for_clearance).to be(false)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "leaves the rest alone: inside the window, running, indefinite, already notified, and not active" do
    inside = rental(owned_until: 13.days.ago)
    running = rental(owned_until: 1.day.from_now)
    indefinite = rental(owned_until: 1.day.from_now).tap { |r| r.update_columns(owned_until: nil) }
    told_at = 30.days.ago.change(usec: 0)
    told = rental(owned_until: 40.days.ago, notified_of_cancellation_at: told_at)
    cancelled = rental(owned_until: 40.days.ago).tap { |r| r.update_columns(state: "cancelled") }

    run(:up)

    expect([inside, running, indefinite, cancelled].map { |r| r.reload.notified_of_cancellation_at }).to all(be_nil)
    expect(told.reload.notified_of_cancellation_at).to eq(told_at)
    expect([inside, running, indefinite, told, cancelled].map { |r| r.reload.staff_notes }).to all(be_nil)
  end

  it "leaves the boundary to the task: a rental ending 14 days ago is still due for a notice" do
    now = Time.current.change(usec: 0)
    edge = rental(owned_until: now - 14.days + 1.minute)
    run(:up)
    expect(edge.reload.notified_of_cancellation_at).to be_nil
    expect(LockerRental.expiry_notice_due).to include(edge)
  end

  it "is safe to run again" do
    old = rental(owned_until: 20.days.ago)
    run(:up)
    first = old.reload.attributes.slice("notified_of_cancellation_at", "staff_notes")
    run(:up)
    expect(old.reload.attributes.slice("notified_of_cancellation_at", "staff_notes")).to eq(first)
  end

  it "reverses: clears exactly the marked rows' timestamp and marker, keeping other notes" do
    plain = rental(owned_until: 20.days.ago)
    noted = rental(owned_until: 30.days.ago)
    noted.update_columns(staff_notes: "call back")
    told_at = 3.days.ago.change(usec: 0)
    genuine = rental(owned_until: 4.days.ago, notified_of_cancellation_at: told_at)
    run(:up)

    run(:down)

    expect(plain.reload).to have_attributes(notified_of_cancellation_at: nil, staff_notes: nil)
    expect(noted.reload).to have_attributes(notified_of_cancellation_at: nil, staff_notes: "call back")
    expect(genuine.reload.notified_of_cancellation_at).to eq(told_at)
  end
end
