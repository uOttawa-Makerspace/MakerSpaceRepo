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
    expect { run_task }.to output(/Sent expiration notice/).to_stdout
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

    it "is 14 days" do
      expect(LockerRental::EXPIRY_NOTICE_WINDOW).to eq(14.days)
    end

    it "notifies a rental that expired just inside the window and the one at its edge, not one just outside, and none that is still running" do
      now = Time.current.change(usec: 0)
      travel_to(now) do
        inside = create(:locker_rental, :active, owned_until: now - 14.days + 1.minute)
        edge = create(:locker_rental, :active, owned_until: now - 14.days)
        outside = create(:locker_rental, :active, owned_until: now - 14.days - 1.minute)
        running = create(:locker_rental, :active, owned_until: now + 1.day)
        indefinite = create(:locker_rental, :active, owned_until: 1.day.from_now).tap { |r| r.update_columns(owned_until: nil) }

        expect(LockerRental.expiry_notice_due).to contain_exactly(inside, edge)
        run_task
        expect(ActionMailer::Base.deliveries.size).to eq(2)
        expect([outside, running, indefinite].map { |r| r.reload.notified_of_cancellation_at }).to all(be_nil)
      end
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
