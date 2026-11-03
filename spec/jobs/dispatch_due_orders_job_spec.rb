# frozen_string_literal: true

require "rails_helper"

# ProcessedOrder is the scheduler; DispatchDueOrdersJob (every minute) hands out what is due and reports what
# nothing has dispatched for hours.
RSpec.describe DispatchDueOrdersJob, type: :job do
  include ActiveJob::TestHelper

  let(:now) { Time.zone.local(2026, 11, 3, 12, 0, 0) }
  let(:reports) { [] }

  before { allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] } }

  def stored(ref, due_in: 0.seconds, status: "received", attempts: 0, **cols)
    order, = ProcessedOrder.receive!(provider: "shopify", order_id: ref, topic: "orders/paid", payload: { "id" => ref })
    order.update_columns(status: status, attempts: attempts, next_attempt_at: now + due_in, **cols)
    order
  end

  def queued_ids = enqueued_jobs.select { |j| j["job_class"] == "ApplyProcessedOrderJob" }.map { |j| j["arguments"].first }

  describe "dispatching" do
    it "hands out a due received order and leases it for 15 minutes" do
      order = stored(1)
      described_class.perform_now(now: now)
      expect(queued_ids).to eq([order.id])
      expect(order.reload.next_attempt_at).to eq(now + ProcessedOrder::LEASE)
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

    it "hands the row out again once its lease has expired (a job that died)" do
      order = stored(1)
      described_class.perform_now(now: now)
      described_class.perform_now(now: now + 14.minutes)
      expect(queued_ids.size).to eq(1)
      described_class.perform_now(now: now + 16.minutes)
      expect(queued_ids).to eq([order.id, order.id])
    end

    it "counts every hand-out in attempts and gives the attempt back when the job cannot be queued" do
      order = stored(1)
      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_return(false)
      ProcessedOrder.dispatch_due(now: now)
      expect(order.reload.attempts).to eq(0)

      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_call_original
      described_class.perform_now(now: now)
      expect(order.reload.attempts).to eq(1)
    end

    it "leaves orders that are not due, applied or failed alone" do
      stored(1, due_in: 5.minutes)
      stored(2, status: "applied")
      stored(3, status: "failed")
      described_class.perform_now(now: now)
      expect(queued_ids).to be_empty
    end

    it "gives the lease back when a job cannot be queued, so the order keeps its due time" do
      order = stored(1, due_in: -3.minutes)
      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_return(false)
      expect(ProcessedOrder.dispatch_due(now: now)).to eq([])
      expect(order.reload.next_attempt_at).to eq(now - 3.minutes)

      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_call_original
      described_class.perform_now(now: now)
      expect(queued_ids).to eq([order.id])
    end

    it "gives the lease back when queueing raises, and never raises itself" do
      order = stored(1)
      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionNotEstablished)
      expect { ProcessedOrder.dispatch_due(now: now) }.not_to raise_error
      expect(order.reload.next_attempt_at).to eq(now)
    end

    it "hands out only the one order asked for" do
      stored(1)
      second = stored(2)
      expect(ProcessedOrder.dispatch_due(id: second.id, now: now)).to eq([second.id])
    end
  end

  describe "reporting stranded orders" do
    it "reports an order more than 2 hours overdue, ids only, once per hour" do
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

    it "does not report an order that is only 1h59m overdue, or one that was dispatched (due in the future)" do
      stored(1, due_in: -(1.hour + 59.minutes))
      stored(2)
      described_class.perform_now(now: now)
      expect(reports).to be_empty
    end

    it "does not report an order the dispatcher hands out, however overdue it was, nor failed or applied ones" do
      stored(1, due_in: -3.hours)
      stored(2, due_in: -3.hours, status: "applied")
      stored(3, due_in: -3.hours, status: "failed")
      described_class.perform_now(now: now) # the first is handed out and leased: in the future, not stranded
      expect(reports).to be_empty
      expect(queued_ids.size).to eq(1)
    end
  end

  describe "a job that dies without raising" do
    def reported_failures = reports.select { |e, _| e.is_a?(ApplyProcessedOrderJob::OrderApplyFailed) }

    it "uses up an attempt per hand-out, so the order ends failed and reported instead of looping" do
      order = stored(1)
      handed_out = (0..ProcessedOrder::MAX_ATTEMPTS + 2).sum do |n|
        before = queued_ids.size # nobody runs the jobs: each lease just expires
        described_class.perform_now(now: now + (n * 16).minutes)
        queued_ids.size - before
      end
      expect(handed_out).to eq(ProcessedOrder::MAX_ATTEMPTS)
      expect(order.reload).to have_attributes(status: "failed", attempts: ProcessedOrder::MAX_ATTEMPTS)
      expect(order.last_error).to be_present
      error, opts = reported_failures.sole
      expect(error.message).to include(order.provider_ref, "10 attempts")
      expect(opts[:context]).to include(shopify_order_id: order.provider_ref, attempts: 10)
    end

    it "counts a run killed by an exception that bypasses StandardError" do
      order = stored(1)
      allow_any_instance_of(ShopOrderApplier).to receive(:call).and_raise(NoMemoryError)
      (ProcessedOrder::MAX_ATTEMPTS + 1).times do |n|
        described_class.perform_now(now: now + (n * 16).minutes)
        ids = queued_ids
        clear_enqueued_jobs
        ids.each do |id|
          ApplyProcessedOrderJob.perform_now(id)
        rescue NoMemoryError
          nil # the worker died: nothing was recorded
        end
      end
      expect(order.reload).to have_attributes(status: "failed", attempts: ProcessedOrder::MAX_ATTEMPTS)
      expect(reported_failures.size).to eq(1)
    end

    it "does not hand out an 11th time or report twice" do
      order = stored(1, attempts: ProcessedOrder::MAX_ATTEMPTS)
      2.times { described_class.perform_now(now: now) }
      expect(queued_ids).to be_empty
      expect(order.reload.status).to eq("failed")
      expect(reported_failures.size).to eq(1)
    end

    it "leaves an order whose last run is still inside its lease alone" do
      order = stored(1, attempts: ProcessedOrder::MAX_ATTEMPTS, due_in: 10.minutes)
      described_class.perform_now(now: now)
      expect(order.reload.status).to eq("received")
      expect(reports).to be_empty
    end
  end

  describe "a backlog of more than one batch" do
    it "is handed out in rounds and not reported as stranded" do
      stub_const("ProcessedOrder::BATCH", 2)
      orders = (1..5).map { |n| stored(n, due_in: -3.hours) }
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
