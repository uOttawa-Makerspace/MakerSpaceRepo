# frozen_string_literal: true

require "rails_helper"

# A staff page rendered while the rental was await_payment, then the Shopify payment activates the rental
# on ANOTHER connection (uncommitted, holding the row lock) while staff submit. The update takes the row lock
# first (lock! reloads), so it waits for the webhook's commit and then sees the paid, active rental:
#   - the stale cancel is REFUSED (never "cancelled" with an applied payment nobody looked at)
#   - a stale "assign" sends no second assigned mail and settles nothing
RSpec.describe "LockerRentals update racing a payment webhook", type: :request do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let(:password) { "asa32A353#" }
  let!(:staff) { create(:user, :staff) }
  let!(:rental) { create(:locker_rental, :await_payment) }

  after do
    LockerPayment.where(locker_rental_id: rental.id).delete_all
    LockerRental.where(id: rental.id).delete_all
    locker = Locker.find_by(id: rental.locker_id)
    locker&.destroy
    locker&.locker_size&.destroy
    User.unscoped.where(id: [staff.id, rental.rented_by_id, rental.decided_by_id]).delete_all
  end

  def log_in!
    post "/login_authentication", params: { username_email: staff.username, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  # The webhook's transaction applies the payment and pauses before its commit; the request is made while it
  # holds the lock, and a releaser thread lets it commit once the request is seen waiting on the lock.
  def request_during_uncommitted_payment
    paused = Queue.new
    resume = Queue.new
    webhook = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        LockerRental.transaction do
          LockerRental.find(rental.id).record_payment(shopify_order_id: "stale-1")
          paused << true
          resume.pop
        end
      end
    rescue StandardError => e
      e
    end
    paused.pop
    releaser = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        deadline = Time.current + 10
        Thread.pass until blocked_backends.positive? || Time.current > deadline
        resume << true
      end
    end
    yield
    releaser.join
    expect(webhook.value).not_to be_a(StandardError)
  end

  it "refuses a stale cancel: the rental stays active with its applied payment" do
    log_in!
    request_during_uncommitted_payment do
      patch locker_rental_path(rental), params: { expected_state: "await_payment", locker_rental: { state: "cancelled" } }
    end

    expect(response).to redirect_to(locker_rental_path(rental))
    expect(flash[:alert]).to include("changed while you had the page open")
    rental.reload
    expect(rental).to be_active
    expect(rental.locker_payments.sole).to be_applied
    expect(LockerRental.cancelled.where(id: rental.id)).to be_empty
  end

  it "a stale assign after the webhook activation sends no second assigned mail and settles nothing" do
    held = create(:locker_payment, :held, locker_rental: LockerRental.find(rental.id), shopify_order_id: "old-held")
    log_in!
    request_during_uncommitted_payment do
      patch locker_rental_path(rental), params: { expected_state: "await_payment", locker_rental: { state: "active", locker_id: rental.locker_id } }
    end

    expect(flash[:alert]).to include("changed while you had the page open")
    expect(held.reload).to be_held
    assigned = enqueued_jobs.select { |j| j["arguments"]&.first(2) == %w[LockerMailer locker_assigned] }
    expect(assigned.size).to eq(1) # the webhook's own mail only
  end

  it "an assign without the expected_state (e.g. JSON) on the already active rental changes no state: no mail, no settlement" do
    held = create(:locker_payment, :held, locker_rental: LockerRental.find(rental.id), shopify_order_id: "old-held-2")
    log_in!
    request_during_uncommitted_payment do
      patch locker_rental_path(rental), params: { locker_rental: { state: "active", locker_id: rental.locker_id } }
    end

    expect(held.reload).to be_held
    assigned = enqueued_jobs.select { |j| j["arguments"]&.first(2) == %w[LockerMailer locker_assigned] }
    expect(assigned.size).to eq(1)
    expect(rental.reload).to be_active
  end
end
