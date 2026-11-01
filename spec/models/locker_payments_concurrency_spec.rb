# frozen_string_literal: true

require "rails_helper"

# Real second connections with committed data, deterministic interleaving (the main thread waits until
# Postgres reports another backend blocked on a lock; no sleeps for ordering).
#   1. a rental activation vs User#deactivate!, in either order: never "active for a renter who was
#      already deactivated" (the renter row is read FOR SHARE, which conflicts with deactivate!'s update)
#   2. two simultaneous deliveries of the same Shopify order record one payment and activate once
RSpec.describe LockerRental, "payments under concurrency", type: :model do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let!(:renter) { create(:user) }
  let!(:rental) { create(:locker_rental, :await_payment, rented_by: renter) }

  after do
    LockerPayment.where(locker_rental_id: rental.id).delete_all
    LockerRental.where(id: rental.id).delete_all
    locker = Locker.find_by(id: rental.locker_id)
    decider = User.unscoped.where(id: rental.decided_by_id)
    locker&.destroy
    locker&.locker_size&.destroy
    User.unscoped.where(id: [renter.id, *decider.pluck(:id)]).delete_all
  end

  # release: the queue the paused thread waits on, so a failure here cannot leave it hanging.
  def wait_until_blocked_on_lock(release, timeout: 5)
    deadline = Time.current + timeout
    loop do
      blocked = ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
      ).to_i
      return if blocked.positive?
      (release << true; raise "no backend became blocked") if Time.current > deadline

      Thread.pass
    end
  end

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  it "activation first: deactivate! waits for the activating transaction, which therefore stays valid" do
    paused = Queue.new
    resume = Queue.new
    activation = in_thread do
      LockerRental.transaction do
        LockerRental.find(rental.id).update!(state: :active)
        paused << true
        resume.pop
      end
      :committed
    end
    paused.pop
    deactivation = in_thread { User.find(renter.id).deactivate! }
    wait_until_blocked_on_lock(resume)
    resume << true

    expect(activation.value).to eq(:committed)
    expect(deactivation.value).not_to be_a(StandardError)
    expect(LockerRental.find(rental.id)).to be_active
    expect(User.unscoped.find(renter.id).deactivated_at).to be_present
  end

  it "deactivation first: the activation waits for the deactivating transaction, then is refused" do
    paused = Queue.new
    resume = Queue.new
    deactivation = in_thread do
      User.transaction do
        User.find(renter.id).deactivate!
        paused << true
        resume.pop
      end
      :committed
    end
    paused.pop
    activation = in_thread do
      candidate = LockerRental.find(rental.id)
      [candidate.update(state: :active), candidate.errors[:rented_by]]
    end
    wait_until_blocked_on_lock(resume)
    resume << true

    expect(deactivation.value).to eq(:committed)
    saved, errors = activation.value
    expect(saved).to be(false)
    expect(errors).to eq(["is deactivated"])
    expect(LockerRental.find(rental.id)).to be_await_payment
  end

  it "a payment delivery waits for a deactivation in flight and then holds the payment" do
    paused = Queue.new
    resume = Queue.new
    deactivation = in_thread do
      User.transaction do
        User.find(renter.id).deactivate!
        paused << true
        resume.pop
      end
      :committed
    end
    paused.pop
    delivery = in_thread { LockerRental.find(rental.id).record_payment(shopify_order_id: "race-1") }
    wait_until_blocked_on_lock(resume)
    resume << true

    expect(deactivation.value).to eq(:committed)
    expect(delivery.value).to have_attributes(status: "held", hold_reason: "renter_ineligible")
    expect(LockerRental.find(rental.id)).to be_await_payment
  end

  it "two simultaneous deliveries of the same order record one payment and activate once" do
    first_in = Queue.new
    resume = Queue.new
    paused_once = Concurrent::AtomicBoolean.new(false)
    allow_any_instance_of(described_class).to receive(:renter_eligible?).and_wrap_original do |original, *args|
      if paused_once.make_true
        first_in << true
        resume.pop
      end
      original.call(*args)
    end

    first = in_thread { LockerRental.find(rental.id).record_payment(shopify_order_id: "race-2") }
    first_in.pop
    second = in_thread { LockerRental.find(rental.id).record_payment(shopify_order_id: "race-2") }
    wait_until_blocked_on_lock(resume) # the second waits on the first's row lock
    resume << true

    results = [first.value, second.value]
    expect(results.grep(StandardError)).to be_empty
    expect(results.compact.size).to eq(1)
    expect(results.compact.first).to be_applied
    expect(LockerPayment.where(shopify_order_id: "race-2").count).to eq(1)
    expect(LockerRental.find(rental.id)).to be_active
    expect(enqueued_jobs.count { |j| j["arguments"]&.first(2) == %w[LockerMailer locker_assigned] }).to eq(1)
  end
end
