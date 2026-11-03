# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261104120000_mark_long_expired_locker_rentals_notified")

RSpec.describe MarkLongExpiredLockerRentalsNotified do
  include ActiveSupport::Testing::TimeHelpers

  def rental(owned_until:, **attrs)
    create(:locker_rental, :active, owned_until: owned_until, **attrs)
  end

  def run(direction) = ActiveRecord::Migration.suppress_messages { described_class.new.public_send(direction) }

  def marker_line(record) = record.staff_notes.lines.last.strip

  it "marks active rentals that expired more than 14 days ago and were never notified, without mailing" do
    old = rental(owned_until: 15.days.ago)
    older_with_notes = rental(owned_until: 200.days.ago)
    older_with_notes.update_columns(staff_notes: "call back")
    ActionMailer::Base.deliveries.clear

    run(:up)

    expect(old.reload.notified_of_cancellation_at).to be_within(1.minute).of(Time.current)
    expect(marker_line(old)).to match(/\A\[20261104120000 \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\] marked notified at deploy; no email sent\z/)
    expect(old.staff_notes).to eq(marker_line(old))
    expect(older_with_notes.reload.staff_notes).to eq("call back\n#{marker_line(old)}")
    expect(old.contacted_for_clearance).to be(false)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "writes one timestamp to every marked row, the one its marker carries" do
    rows = [rental(owned_until: 20.days.ago), rental(owned_until: 30.days.ago)]
    run(:up)
    stamps = rows.map { |r| r.reload.notified_of_cancellation_at }
    expect(stamps.uniq.size).to eq(1)
    expect(marker_line(rows.first)).to include(stamps.first.utc.iso8601)
    expect(stamps.first.usec).to eq(0)
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

  it "leaves the boundary to the task: a rental that ended just inside 14 days is not marked, and the task still has it a day later" do
    now = Time.current.change(usec: 0)
    edge = rental(owned_until: now - 14.days + 1.minute)
    run(:up)
    expect(edge.reload.notified_of_cancellation_at).to be_nil
    expect(LockerRental.expiry_notice_due(now + 1.day)).to include(edge)
  end

  it "is safe to run again" do
    old = rental(owned_until: 20.days.ago)
    run(:up)
    first = old.reload.attributes.slice("notified_of_cancellation_at", "staff_notes")
    run(:up)
    expect(old.reload.attributes.slice("notified_of_cancellation_at", "staff_notes")).to eq(first)
  end

  describe "down" do
    it "restores NULL notes, empty notes and existing text, and clears the timestamp only on the marked rows" do
      null_notes = rental(owned_until: 20.days.ago)
      empty_notes = rental(owned_until: 21.days.ago).tap { |r| r.update_columns(staff_notes: "") }
      text_notes = rental(owned_until: 22.days.ago).tap { |r| r.update_columns(staff_notes: "call back\nsecond line") }
      told_at = 3.days.ago.change(usec: 0)
      genuine = rental(owned_until: 4.days.ago, notified_of_cancellation_at: told_at)
      lookalike = rental(owned_until: 25.days.ago, notified_of_cancellation_at: told_at)
      lookalike.update_columns(staff_notes: "marked notified at deploy; no email sent")
      mid = rental(owned_until: 26.days.ago, notified_of_cancellation_at: told_at)
      run(:up)
      line = marker_line(null_notes.reload)
      mid.update_columns(staff_notes: "#{line}\nand more", notified_of_cancellation_at: told_at)
      expect(empty_notes.reload.staff_notes).to eq("\n#{line}")

      run(:down)

      expect(null_notes.reload).to have_attributes(notified_of_cancellation_at: nil, staff_notes: nil)
      expect(empty_notes.reload).to have_attributes(notified_of_cancellation_at: nil, staff_notes: "")
      expect(text_notes.reload).to have_attributes(notified_of_cancellation_at: nil, staff_notes: "call back\nsecond line")
      expect(genuine.reload.notified_of_cancellation_at).to eq(told_at)
      expect(lookalike.reload).to have_attributes(notified_of_cancellation_at: told_at, staff_notes: "marked notified at deploy; no email sent")
      expect(mid.reload).to have_attributes(notified_of_cancellation_at: told_at, staff_notes: "#{line}\nand more")
    end

    it "keeps the real notice of a marked rental that was renewed and notified again, and still removes the marker line" do
      renewed = rental(owned_until: 30.days.ago)
      untouched = rental(owned_until: 31.days.ago)
      run(:up)
      real_notice = 2.days.ago.change(usec: 0)
      renewed.update!(owned_until: 3.days.ago) # a renewal clears the notice ...
      renewed.update_columns(notified_of_cancellation_at: real_notice) # ... and the next expiry is announced

      run(:down)

      expect(renewed.reload).to have_attributes(notified_of_cancellation_at: real_notice, staff_notes: nil)
      expect(untouched.reload).to have_attributes(notified_of_cancellation_at: nil, staff_notes: nil)
    end
  end
end
