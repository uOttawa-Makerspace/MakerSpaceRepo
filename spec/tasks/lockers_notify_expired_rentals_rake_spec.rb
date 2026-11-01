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
end
