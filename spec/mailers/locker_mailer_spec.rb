# frozen_string_literal: true

require "rails_helper"

# Mail to the renter is never delivered to a soft-deleted or deactivated account (checked when the mail is
# built, i.e. when the job runs). Mail to staff (new request) is not the renter's and always goes.
RSpec.describe LockerMailer, type: :mailer do
  let(:rental) { create(:locker_rental, :active, owned_until: 2.days.ago).tap { |r| r.update!(state: :cancelled) } }
  let(:renter) { rental.rented_by }

  def renter_mails(rental)
    [
      described_class.with(locker_rental: rental).locker_assigned,
      described_class.with(locker_rental: rental).locker_checkout,
      described_class.with(locker_rental: rental).locker_cancelled,
      described_class.with(locker_rental: rental).rental_expired,
      described_class.with(locker_rental: rental, moved_locker: nil, moved_date: nil).locker_moved
    ]
  end

  it "builds every renter mail for an eligible renter" do
    renter_mails(rental).each { |m| expect(m.message.to).to eq([renter.email]) }
  end

  it "sends nothing to a deactivated renter" do
    renter.deactivate!
    renter_mails(LockerRental.find(rental.id)).each do |m|
      expect { m.deliver_now }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  it "sends nothing to a soft-deleted renter" do
    renter.update_columns(deleted: true)
    renter_mails(LockerRental.find(rental.id)).each do |m|
      expect { m.deliver_now }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  it "drops a mail queued before the renter was deactivated, when its job runs" do
    expect do
      described_class.with(locker_rental: rental).locker_assigned.deliver_later
    end.to have_enqueued_mail(described_class, :locker_assigned)
    renter.deactivate!
    expect { perform_enqueued_jobs }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "still mails staff about a new request when the renter is deactivated" do
    request = create(:locker_rental, :reviewing)
    request.rented_by.deactivate!
    expect { described_class.with(locker_rental: LockerRental.find(request.id)).locker_requested.deliver_now }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
  end

  describe "cancellation mail" do
    def body_of(rental)
      described_class.with(locker_rental: LockerRental.find(rental.id)).locker_cancelled.body.encoded
    end

    it "gives the date the cancellation was recorded for a rental with a locker" do
      expect(body_of(rental)).to include(rental.cancelled_at.to_date.to_formatted_s(:long))
    end

    it "renders for a rental cancelled before its end date" do
      future = create(:locker_rental, :active, owned_until: 2.months.from_now).tap { |r| r.update!(state: :cancelled) }
      expect(body_of(future)).to include(future.cancelled_at.to_date.to_formatted_s(:long))
    end

    it "renders for a cancelled rental that has no recorded cancellation date" do
      future = create(:locker_rental, :active, owned_until: 2.months.from_now).tap { |r| r.update!(state: :cancelled) }
      future.update_columns(cancelled_at: nil)
      expect(body_of(future)).to include("has been cancelled.")
    end

    it "renders for a request cancelled before a locker was assigned" do
      request = create(:locker_rental, :reviewing).tap { |r| r.update!(state: :cancelled, decided_by: create(:user, :staff)) }
      expect(body_of(request)).to include("has been rejected")
    end
  end
end
