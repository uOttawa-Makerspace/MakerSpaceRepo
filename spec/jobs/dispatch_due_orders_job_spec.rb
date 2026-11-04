# frozen_string_literal: true

require "rails_helper"

# ProcessedOrder is the scheduler; DispatchDueOrdersJob (every minute) hands out what is due and reports what
# nothing has dispatched for hours.
RSpec.describe DispatchDueOrdersJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 11, 3, 12, 0, 0) }
  let(:reports) { [] }

  before { allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] } }

  def stored(ref, due_in: 0.seconds, status: "received", attempts: 0, **cols)
    order, = ProcessedOrder.receive!(provider: "shopify", order_id: ref, topic: "orders/paid", payload: { "id" => ref })
    order.update_columns(status: status, attempts: attempts, next_attempt_at: now + due_in, **cols)
    order
  end

  def queued_ids = enqueued_jobs.select { |j| j["job_class"] == "ApplyProcessedOrderJob" }.map { |j| j["arguments"].first }

  # Runs the queued jobs as a worker would and returns the ids it ran. A run killed by an exception that bypasses
  # StandardError (out of memory, a hard kill) is simulated with NoMemoryError: the worker dies, nothing is recorded.
  def run_queued_jobs
    ids = queued_ids
    ids.size.times do
      perform_enqueued_jobs(only: ApplyProcessedOrderJob)
    rescue NoMemoryError
      nil
    end
    clear_enqueued_jobs
    ids
  end

  describe "dispatching" do
    it "marks the spent orders failed once per run, however many rounds a backlog takes" do
      full = Array.new(ProcessedOrder::BATCH) { |i| i + 1 }
      rounds = [full, full, full, []]
      allow(ProcessedOrder).to receive(:dispatch_due).and_wrap_original { |_m, **| rounds.shift }
      expect(ProcessedOrder).to receive(:fail_exhausted).once.ordered
      expect(ProcessedOrder).to receive(:dispatch_due).with(now: now, skip_fail_exhausted: true).exactly(4).times.ordered

      described_class.perform_now(now: now)
    end

    it "reports a failure of the spent-order step and still dispatches and reports stranded orders" do
      order = stored(1)
      allow(ProcessedOrder).to receive(:fail_exhausted).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect(ProcessedOrder).to receive(:report_stranded).with(now: now)

      expect { described_class.perform_now(now: now) }.not_to raise_error

      expect(queued_ids).to eq([order.id])
      error, opts = reports.find { |e, _| e.is_a?(ActiveRecord::StatementInvalid) }
      expect(error).to be_present
      expect(opts[:context]).to eq(step: "fail_exhausted")
    end

    it "keeps dispatch_due failing the spent orders when it is called alone" do
      spent = stored(1, attempts: ProcessedOrder::MAX_ATTEMPTS)
      ProcessedOrder.dispatch_due(now: now)
      expect(spent.reload.status).to eq("failed")
    end

    it "leaves the spent orders to the caller with skip_fail_exhausted: true" do
      spent = stored(1, attempts: ProcessedOrder::MAX_ATTEMPTS)
      ProcessedOrder.dispatch_due(now: now, skip_fail_exhausted: true)
      expect(spent.reload.status).to eq("received")
    end

    it "hands out a due received order by leasing it for 15 minutes and touches nothing else" do
      order = stored(1)
      before = order.reload.attributes.slice("attempts", "next_attempt_at", "updated_at", "status")
      described_class.perform_now(now: now)
      expect(queued_ids).to eq([order.id])
      expect(order.reload.leased_until).to eq(now + ProcessedOrder::LEASE)
      expect(order.attributes.slice("attempts", "next_attempt_at", "updated_at", "status")).to eq(before)
    end

    it "queues the job with the lease as its token, and the run counts its attempt against it" do
      order = stored(1)
      allow_any_instance_of(ShopOrderApplier).to receive(:call)
      described_class.perform_now(now: now)
      expect(enqueued_jobs.first["arguments"].size).to eq(2)
      expect(run_queued_jobs).to eq([order.id])
      expect(order.reload.attempts).to eq(1)
    end

    it "hands a row out once however often it is dispatched (a double dispatch)" do
      order = stored(1)
      2.times { described_class.perform_now(now: now) }
      ProcessedOrder.dispatch_due(id: order.id, now: now)
      expect(queued_ids).to eq([order.id])
    end

    it "hands a row out once to two concurrent dispatchers" do
      order = stored(1)
      results = 2.times.map do
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { ProcessedOrder.dispatch_due(now: now) } }
      end.map(&:value)
      expect(results.flatten).to eq([order.id])
      expect(queued_ids).to eq([order.id])
    end

    it "hands the row out again once its lease has expired (a job that died), without moving its due time" do
      order = stored(1, due_in: -1.minute)
      described_class.perform_now(now: now)
      described_class.perform_now(now: now + 14.minutes)
      expect(queued_ids.size).to eq(1)
      described_class.perform_now(now: now + 16.minutes)
      expect(queued_ids).to eq([order.id, order.id])
      expect(order.reload.next_attempt_at).to eq(now - 1.minute)
    end

    it "leaves orders that are not due, applied or failed alone" do
      stored(1, due_in: 5.minutes)
      stored(2, status: "applied")
      stored(3, status: "failed")
      described_class.perform_now(now: now)
      expect(queued_ids).to be_empty
    end

    it "gives the lease back when a job cannot be queued, so the next dispatch hands it out" do
      order = stored(1, due_in: -3.minutes)
      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_return(false)
      expect(ProcessedOrder.dispatch_due(now: now)).to eq([])
      expect(order.reload).to have_attributes(leased_until: nil, attempts: 0, next_attempt_at: now - 3.minutes)

      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_call_original
      described_class.perform_now(now: now)
      expect(queued_ids).to eq([order.id])
    end

    it "gives the lease back when queueing raises, and never raises itself" do
      order = stored(1)
      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionNotEstablished)
      expect { ProcessedOrder.dispatch_due(now: now) }.not_to raise_error
      expect(order.reload.leased_until).to be_nil
    end

    it "hands out only the one order asked for" do
      stored(1)
      second = stored(2)
      expect(ProcessedOrder.dispatch_due(id: second.id, now: now)).to eq([second.id])
    end
  end

  describe "reporting stranded orders" do
    it "reports an order that has been due for more than 2 hours, ids only, once per hour" do
      order = stored(1, due_in: -(2.hours + 1.minute))
      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_return(false) # nothing manages to dispatch it

      reported = (0..125).select do |minute|
        before = reports.size
        described_class.perform_now(now: now + minute.minutes)
        reports.size > before
      end
      expect(reported).to eq([0, 61, 122]) # more than an hour after the previous report
      error, opts = reports.first
      expect(error).to be_a(described_class::StrandedOrder)
      expect(error.message).to include(order.provider_ref)
      expect(opts[:context]).to eq(shopify_order_id: order.provider_ref, attempts: 0)
      expect(order.reload.reported_at).to eq(now + 122.minutes)
    end

    it "reports an order handed out again and again while no run starts (workers down), and never fails it" do
      order = stored(1)
      handed_out = 0
      reported = (0..20).select do |n|
        before = [reports.size, queued_ids.size]
        described_class.perform_now(now: now + (n * 16).minutes) # each lease expires unused
        handed_out += queued_ids.size - before.last
        reports.size > before.first
      end
      expect(handed_out).to eq(21)
      expect(order.reload).to have_attributes(status: "received", attempts: 0)
      expect(reported).to eq([8, 12, 16, 20])
      expect(reports.map(&:first)).to all(be_a(described_class::StrandedOrder))
    end

    it "does not report an order that has been due for only 1h59m, or one not yet due" do
      stored(1, due_in: -(1.hour + 59.minutes))
      stored(2, due_in: 1.hour)
      described_class.perform_now(now: now)
      expect(reports).to be_empty
    end

    it "reports an order due for 3 hours even though it was just handed out, but not failed or applied ones" do
      stored(1, due_in: -3.hours)
      stored(2, due_in: -3.hours, status: "applied")
      stored(3, due_in: -3.hours, status: "failed")
      described_class.perform_now(now: now)
      expect(reports.map { |_, o| o[:context][:shopify_order_id] }).to eq(["1"])
    end
  end

  describe "runs that die" do
    def reported_failures = reports.select { |e, _| e.is_a?(ApplyProcessedOrderJob::OrderApplyFailed) }

    it "ends failed and reported after MAX_ATTEMPTS runs that started and died, and is not handed out an 11th time" do
      order = stored(1)
      allow_any_instance_of(ShopOrderApplier).to receive(:call).and_raise(NoMemoryError)
      runs = (0..ProcessedOrder::MAX_ATTEMPTS + 2).sum do |n|
        # A run takes a fresh lease from the clock, so the clock is the simulated one for the whole round.
        travel_to(now + (n * 16).minutes) do
          described_class.perform_now
          run_queued_jobs.size
        end
      end
      expect(runs).to eq(ProcessedOrder::MAX_ATTEMPTS)
      expect(order.reload).to have_attributes(status: "failed", attempts: ProcessedOrder::MAX_ATTEMPTS, leased_until: nil)
      expect(order.last_error).to eq("the last attempt did not finish")
      error, opts = reported_failures.sole
      expect(error.message).to include(order.provider_ref, "10 attempts")
      expect(opts[:context]).to include(shopify_order_id: order.provider_ref, attempts: 10)
    end

    it "does not hand out an order whose last attempt is spent, nor report it twice" do
      order = stored(1, attempts: ProcessedOrder::MAX_ATTEMPTS, leased_until: now - 1.minute)
      2.times { described_class.perform_now(now: now) }
      expect(queued_ids).to be_empty
      expect(order.reload.status).to eq("failed")
      expect(reported_failures.size).to eq(1)
    end

    it "keeps the last real error and says the last attempt did not finish" do
      order = stored(1, attempts: ProcessedOrder::MAX_ATTEMPTS, leased_until: now - 1.minute, last_error: "ArgumentError: bad")
      described_class.perform_now(now: now)
      expect(order.reload).to have_attributes(status: "failed", last_error: "ArgumentError: bad (then the last attempt did not finish)")
    end

    it "also fails a spent order left with no lease, as a backstop" do
      order = stored(1, attempts: ProcessedOrder::MAX_ATTEMPTS, leased_until: nil)
      described_class.perform_now(now: now)
      expect(queued_ids).to be_empty
      expect(order.reload).to have_attributes(status: "failed", leased_until: nil)
      expect(reported_failures.sole.last[:context]).to include(shopify_order_id: order.provider_ref, attempts: 10)
    end

    it "leaves an order whose last run is still inside its lease alone" do
      order = stored(1, attempts: ProcessedOrder::MAX_ATTEMPTS, leased_until: now + 10.minutes)
      described_class.perform_now(now: now)
      expect(order.reload.status).to eq("received")
      expect(reported_failures).to be_empty
    end

    it "gives an order that fails normally exactly MAX_ATTEMPTS started runs" do
      order = stored(1, due_in: -1.day)
      allow_any_instance_of(ShopOrderApplier).to receive(:call).and_raise(ArgumentError, "bad")
      runs = (0..ProcessedOrder::MAX_ATTEMPTS + 2).sum do |n|
        described_class.perform_now(now: Time.current + (n * 20).hours) # past every backoff
        run_queued_jobs.size
      end
      expect(runs).to eq(ProcessedOrder::MAX_ATTEMPTS)
      expect(order.reload).to have_attributes(status: "failed", attempts: ProcessedOrder::MAX_ATTEMPTS, leased_until: nil)
      expect(order.last_error).to eq("ArgumentError: bad")
      expect(reported_failures.size).to eq(1)
      retrying = reports.select { |e, _| e.is_a?(ApplyProcessedOrderJob::OrderApplyRetrying) }
      expect(retrying.map { |_, o| o[:context][:attempts] }).to eq([1, 5])
    end

    it "does nothing for a duplicate job whose token is stale" do
      order = stored(1)
      described_class.perform_now(now: now)
      stale = order.reload.leased_until - 1.hour
      expect_any_instance_of(ShopOrderApplier).not_to receive(:call)
      ApplyProcessedOrderJob.perform_now(order.id, stale)
      expect(order.reload).to have_attributes(attempts: 0, status: "received", leased_until: now + ProcessedOrder::LEASE)
    end
  end

  describe "a backlog of more than one batch" do
    it "is handed out in rounds and not reported as stranded" do
      stub_const("ProcessedOrder::BATCH", 2)
      orders = (1..5).map { |n| stored(n, due_in: -1.hour) }
      described_class.perform_now(now: now)
      expect(queued_ids).to match_array(orders.map(&:id))
      expect(reports).to be_empty
    end
  end

  describe "the retry schedule" do
    it "backs off by attempts: about 34 hours over the nine waits" do
      waits = (1..9).map { |n| ProcessedOrder.backoff(n) }
      expect(waits.map(&:to_i)).to eq([61, 92, 303, 1084, 3185, 7836, 16_867, 32_828, 59_109])
      expect(waits.sum).to be_between(33.hours, 35.hours)
    end
  end
end
