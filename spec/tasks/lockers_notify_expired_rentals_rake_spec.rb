# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "lockers:notify_expired_rentals" do
  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lockers:notify_expired_rentals")
    Rake::Task["lockers:notify_expired_rentals"].reenable
    ActionMailer::Base.deliveries.clear
  end

  def expired_rental
    create(:locker_rental, :active, owned_until: 2.days.ago)
  end

  def run_task
    perform_enqueued_jobs { Rake::Task["lockers:notify_expired_rentals"].invoke }
  end

  it "notifies an eligible renter and records the bookkeeping columns" do
    rental = expired_rental
    expect { run_task }.to output(/Sent expiration notice for Locker Rental ##{rental.id}/).to_stdout
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[rental.rented_by.email]])
    expect(rental.reload).to have_attributes(contacted_for_clearance: true)
    expect(rental.notified_of_cancellation_at).to be_present
  end

  {
    "deactivated" => ->(u) { u.deactivate! },
    "soft-deleted" => ->(u) { u.update_columns(deleted: true) }
  }.each do |label, change|
    it "skips the whole row for a #{label} renter: no mail, and the 'notified' bookkeeping is NOT set, so staff still chase it" do
      rental = expired_rental
      change.call(rental.rented_by)
      expect { run_task }.to output(/Skipped Locker Rental ##{rental.id}/).to_stdout
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(rental.reload).to have_attributes(contacted_for_clearance: false, notified_of_cancellation_at: nil)
    end
  end

  describe "the notice window (LockerRental::EXPIRY_NOTICE_WINDOW)" do
    include ActiveSupport::Testing::TimeHelpers

    it "is 14 days, with one grace day" do
      expect(LockerRental::EXPIRY_NOTICE_WINDOW).to eq(14.days)
      expect(LockerRental::EXPIRY_NOTICE_GRACE).to eq(1.day)
    end

    it "notifies rentals that expired inside window plus grace, not one just outside, and none that is still running" do
      now = Time.current.change(usec: 0)
      travel_to(now) do
        inside = create(:locker_rental, :active, owned_until: now - 14.days + 1.minute)
        edge = create(:locker_rental, :active, owned_until: now - 15.days)
        outside = create(:locker_rental, :active, owned_until: now - 15.days - 1.minute)
        running = create(:locker_rental, :active, owned_until: now + 1.day)
        indefinite = create(:locker_rental, :active, owned_until: 1.day.from_now).tap { |r| r.update_columns(owned_until: nil) }

        expect(LockerRental.expiry_notice_due).to contain_exactly(inside, edge)
        run_task
        expect(ActionMailer::Base.deliveries.size).to eq(2)
        expect([outside, running, indefinite].map { |r| r.reload.notified_of_cancellation_at }).to all(be_nil)
      end
    end

    it "sends one mail per rental when two runs overlap (the second sees the rental the first already claimed)" do
      rental = expired_rental
      stale = LockerRental.expiry_notice_due.to_a
      run_task
      Rake::Task["lockers:notify_expired_rentals"].reenable
      relation = Object.new
      relation.define_singleton_method(:find_each) { |&blk| stale.each(&blk) }
      real = LockerRental.method(:expiry_notice_due)
      allow(LockerRental).to receive(:expiry_notice_due) { |*args| args.empty? ? relation : real.call(*args) }
      expect { run_task }.not_to(change { ActionMailer::Base.deliveries.size })
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[rental.rented_by.email]])
    end

    it "logs the rental id, never the renter's address" do
      rental = expired_rental
      lines = []
      LockerRental.notify_expired_rentals!(log: ->(l) { lines << l })
      expect(lines.join).to include("##{rental.id}")
      expect(lines.join).not_to include(rental.rented_by.email)
    end

    it "releases its claim and leaves the contacted flag unset when the mail cannot be enqueued, so the next run mails it" do
      rental = expired_rental
      allow(LockerMailer).to receive(:with).and_raise(RuntimeError, "queue down")
      expect { LockerRental.notify_expired_rentals! }.to raise_error("queue down")
      expect(rental.reload).to have_attributes(notified_of_cancellation_at: nil, contacted_for_clearance: false)
    end

    it "releases only a claim that is still ours" do
      rental = expired_rental
      other = 1.hour.from_now.change(usec: 0)
      allow(LockerMailer).to receive(:with) do
        rental.update_columns(notified_of_cancellation_at: other) # another run re-claimed it
        raise "queue down"
      end
      expect { LockerRental.notify_expired_rentals! }.to raise_error("queue down")
      expect(rental.reload.notified_of_cancellation_at).to eq(other)
    end

    it "sets the contacted flag after the mail is enqueued, on the claim it made" do
      rental = expired_rental
      LockerRental.notify_expired_rentals!
      expect(rental.reload).to have_attributes(contacted_for_clearance: true)
      expect(rental.notified_of_cancellation_at).to be_present
    end

    it "does not claim or mail a rental renewed (or cancelled) between loading and claiming" do
      renewed = expired_rental
      cancelled = expired_rental
      stale = LockerRental.expiry_notice_due.to_a
      renewed.update!(owned_until: 3.months.from_now)
      cancelled.update_columns(state: "cancelled")
      relation = Object.new
      relation.define_singleton_method(:find_each) { |&blk| stale.each(&blk) }
      real = LockerRental.method(:expiry_notice_due)
      allow(LockerRental).to receive(:expiry_notice_due) { |*args| args.empty? ? relation : real.call(*args) }

      expect(LockerRental.notify_expired_rentals!).to eq(0)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect([renewed, cancelled].map { |r| r.reload.notified_of_cancellation_at }).to all(be_nil)
    end

    it "mails a rental once: a second run finds nothing" do
      expired_rental
      run_task
      Rake::Task["lockers:notify_expired_rentals"].reenable
      expect { run_task }.not_to(change { ActionMailer::Base.deliveries.size })
    end

    it "does not touch a cancelled rental" do
      rental = create(:locker_rental, :active, owned_until: 2.days.ago)
      rental.update_columns(state: "cancelled")
      run_task
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
