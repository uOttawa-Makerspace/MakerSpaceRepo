# frozen_string_literal: true

require "rails_helper"

# Two runs of the job on one stored order, on real connections with committed data: the second waits on the
# first's row lock (FOR UPDATE), then finds the order applied and does nothing. Deterministic interleaving as in
# locker_payments_concurrency_spec: the main thread waits until Postgres reports another backend blocked on a lock.
RSpec.describe ApplyProcessedOrderJob, "under concurrency", type: :job do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let!(:user) { create(:user, :regular_user) }
  let(:order_id) { 8_100_000_000_001 }
  let(:payload) do
    { id: order_id, customer: { email: user.email }, line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }] }
  end
  let!(:stored) do
    ProcessedOrder.receive!(provider: "shopify", order_id: order_id, topic: "orders/paid",
                            payload: JSON.parse(payload.to_json)).first
  end

  before do
    block_external_http!
    allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields).and_return(nil)
  end

  after do
    CcMoney.where(user_id: user.id).delete_all
    ProcessedOrder.where(provider_ref: order_id.to_s).delete_all
    User.unscoped.where(id: user.id).delete_all
  end

  # The dispatcher's hand-out: a fresh lease on the row, which is the token of the run it queues.
  def lease!(order)
    token = (Time.current + ProcessedOrder::LEASE).floor(6)
    ProcessedOrder.where(id: order.id).update_all(leased_until: token)
    token
  end

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

  def pause_first_credit_then_fail
    first_in = Queue.new
    resume = Queue.new
    failed_once = Concurrent::AtomicBoolean.new(false)
    allow(CcMoney).to receive(:create!).and_wrap_original do |original, *args|
      if failed_once.make_true
        first_in << true
        resume.pop
        raise ActiveRecord::StatementInvalid, "boom"
      end
      original.call(*args)
    end
    [first_in, resume]
  end

  def pause_first_credit
    first_in = Queue.new
    resume = Queue.new
    paused_once = Concurrent::AtomicBoolean.new(false)
    allow(CcMoney).to receive(:create!).and_wrap_original do |original, *args|
      if paused_once.make_true
        first_in << true # the first run holds the order's row lock, uncommitted
        resume.pop
      end
      original.call(*args)
    end
    [first_in, resume]
  end

  # The first run pauses after it started and before it takes the order's row lock; returns [reached, go].
  def pause_first_run_before_lock
    reached = Queue.new
    go = Queue.new
    paused_once = Concurrent::AtomicBoolean.new(false)
    allow_any_instance_of(ShopOrderApplier).to receive(:resolve_references).and_wrap_original do |original, *args|
      if paused_once.make_true
        reached << true
        go.pop
      end
      original.call(*args)
    end
    [reached, go]
  end

  it "applies one order once when a run outlives its lease and the order is handed out again" do
    reached, go = pause_first_run_before_lock
    first_in, resume = pause_first_credit
    token = lease!(stored)
    first = in_thread { described_class.perform_now(stored.id, token) }
    reached.pop
    newer = lease!(stored) # the first run outlived its lease: the order is handed out again
    go << true
    first_in.pop # the first run holds the order's row lock
    second = in_thread { described_class.perform_now(stored.id, newer) }
    wait_until_blocked_on_lock(resume) # the newer run waits to start
    resume << true

    expect([first.value, second.value]).not_to include(a_kind_of(StandardError))
    expect(user.cc_moneys.pluck(:cc)).to eq([20]) # applied by the older run, once
    expect(stored.reload).to have_attributes(status: "applied", attempts: 1, leased_until: nil) # the newer run did nothing
  end

  it "applies it again in a later run when the first fails after its writes" do
    first_in, resume = pause_first_credit_then_fail
    token = lease!(stored)
    allow(Rails.error).to receive(:report)
    first = in_thread { described_class.perform_now(stored.id, token) }
    first_in.pop
    resume << true
    first.join

    expect(user.cc_moneys.count).to eq(0)
    expect(stored.reload).to have_attributes(status: "received", attempts: 1, leased_until: nil)
    described_class.perform_now(stored.id, lease!(stored))
    expect(user.cc_moneys.pluck(:cc)).to eq([20])
    expect(stored.reload).to have_attributes(status: "applied", attempts: 2)
  end

  it "gives up waiting for a run that holds the order longer than the lock bound, and the order is retried" do
    stub_const("ApplicationRecord::LOCK_TIMEOUT", "300ms")
    allow(Rails.error).to receive(:report)
    first_in, resume = pause_first_credit
    token = lease!(stored)
    first = in_thread { described_class.perform_now(stored.id, token) }
    first_in.pop
    running = stored.reload.leased_until # the lease the first run took when it started
    second = in_thread { described_class.perform_now(stored.id, running) } # a job that would start on that lease
    wait_until_blocked_on_lock(resume)
    finished = second.join(5)
    resume << true
    first.join

    expect(finished).not_to be_nil
    expect(user.cc_moneys.pluck(:cc)).to eq([20])
    expect(stored.reload).to have_attributes(status: "applied")
    expect(stored.last_error).to be_nil
  end

  it "never waits on an order a running apply holds: neither marking exhausted orders failed nor handing out" do
    allow(Rails.error).to receive(:report)
    stored.update_columns(attempts: ProcessedOrder::MAX_ATTEMPTS, leased_until: 1.minute.ago)
    held = Queue.new
    release = Queue.new
    holder = in_thread do
      ProcessedOrder.transaction do
        ProcessedOrder.lock.find(stored.id)
        held << true
        release.pop
      end
    end
    held.pop
    begin
      skipped = Timeout.timeout(5) { ProcessedOrder.fail_exhausted }
      handed_out = Timeout.timeout(5) { ProcessedOrder.dispatch_due }
    ensure
      release << true
      holder.join
    end

    expect([skipped, handed_out]).to eq([[], []])
    expect(stored.reload.status).to eq("received")
    expect(ProcessedOrder.fail_exhausted).to eq([stored.provider_ref])
    expect(stored.reload).to have_attributes(status: "failed", leased_until: nil)
  end

  describe "a locker order whose rental row is held by someone else" do
    let!(:rental) { create(:locker_rental, :await_payment) }
    let!(:locker_stored) do
      ProcessedOrder.receive!(
        provider: "shopify", order_id: 8_100_000_000_002, topic: "orders/paid",
        payload: JSON.parse({ id: 8_100_000_000_002, tags: [LockerRental.draft_order_operating_tag],
                              metafields: [{ namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s }] }.to_json)
      ).first
    end

    after do
      LockerPayment.where(locker_rental_id: rental.id).delete_all
      LockerRental.where(id: rental.id).delete_all
      ProcessedOrder.where(id: locker_stored.id).delete_all
      locker = Locker.find_by(id: rental.locker_id)
      decider = User.unscoped.where(id: rental.decided_by_id).pluck(:id)
      locker&.destroy
      locker&.locker_size&.destroy
      User.unscoped.where(id: [rental.rented_by_id, *decider]).delete_all
    end

    it "times out instead of pinning the worker: the attempt is recorded and the order stays received" do
      stub_const("ApplicationRecord::LOCK_TIMEOUT", "300ms")
      held = Queue.new
      release = Queue.new
      holder = in_thread do
        LockerRental.transaction do
          LockerRental.lock.find(rental.id)
          held << true
          release.pop
        end
      end
      held.pop
      begin
        described_class.perform_now(locker_stored.id, lease!(locker_stored))
      ensure
        release << true
        holder.join
      end

      expect(locker_stored.reload).to have_attributes(status: "received", attempts: 1)
      expect(locker_stored.last_error).to include("LockWaitTimeout")
      expect(LockerPayment.where(locker_rental_id: rental.id)).to be_empty

      described_class.perform_now(locker_stored.id, lease!(locker_stored))
      expect([locker_stored.reload.status, rental.reload.state]).to eq(["applied", "active"])
    end
  end
end
