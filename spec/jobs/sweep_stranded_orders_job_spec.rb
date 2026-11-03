# frozen_string_literal: true

require "rails_helper"

RSpec.describe SweepStrandedOrdersJob, type: :job do
  include ActiveJob::TestHelper

  let(:now) { Time.zone.local(2026, 11, 3, 12, 0, 0) }
  let(:reports) { [] }

  before { allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] } }

  def stored(ref, updated_ago:, status: "received", attempts: 0)
    order, = ProcessedOrder.receive!(provider: "shopify", order_id: ref, topic: "orders/paid", payload: { "id" => ref })
    order.update_columns(status: status, attempts: attempts, updated_at: now - updated_ago)
    order
  end

  def queued_ids = enqueued_jobs.select { |j| j["job_class"] == "ApplyProcessedOrderJob" }.map { |j| j["arguments"].first }

  it "queues a received order nothing has touched for longer than the grace period" do
    order = stored(1, updated_ago: 20.minutes)
    described_class.perform_now(now: now)
    expect(queued_ids).to eq([order.id])
  end

  it "leaves recent orders, applied orders and failed orders alone" do
    stored(1, updated_ago: 5.minutes)
    stored(2, updated_ago: 3.hours, status: "applied")
    stored(3, updated_ago: 3.hours, status: "failed")
    described_class.perform_now(now: now)
    expect(queued_ids).to be_empty
  end

  it "waits for the retry an order is due: not before its backoff plus the grace, then queues it" do
    waiting = stored(1, updated_ago: 2.hours, attempts: 6) # next retry about 2h10m after its last attempt
    expect(ApplyProcessedOrderJob.wait_for(6)).to be > 2.hours
    described_class.perform_now(now: now)
    expect(queued_ids).to be_empty

    waiting.update_columns(updated_at: now - (ApplyProcessedOrderJob.wait_for(6) + 16.minutes))
    described_class.perform_now(now: now)
    expect(queued_ids).to eq([waiting.id])
  end

  it "does not touch the row when it queues it again" do
    order = stored(1, updated_ago: 30.minutes)
    expect { described_class.perform_now(now: now) }.not_to(change { order.reload.updated_at })
  end

  it "reports an order untouched for 2 hours, ids only, once per hour across the 10-minute sweeps" do
    order = stored(1, updated_ago: 2.hours + 3.minutes)
    reported_at = (0..24).select do |step|
      before = reports.size
      described_class.perform_now(now: now + (step * 10).minutes)
      reports.size > before
    end
    # sweeps at +0 (2h03m old) .. +240 minutes (6h03m old): one report per hour of age, six sweeps apart
    expect(reported_at).to eq([0, 6, 12, 18, 24])
    error, opts = reports.first
    expect(error).to be_a(described_class::StrandedOrder)
    expect(error.message).to include(order.provider_ref)
    expect(opts[:context]).to eq(shopify_order_id: order.provider_ref, attempts: 0, status: "received")
  end

  it "reports nothing for an order younger than 2 hours" do
    stored(1, updated_ago: 1.hour + 59.minutes)
    described_class.perform_now(now: now)
    expect(reports).to be_empty
  end

  it "covers an order whose failed-state write raised: it stays received and is queued again" do
    order = stored(1, updated_ago: 17.hours, attempts: 10)
    allow(ProcessedOrder).to receive(:mark_failed!).and_raise(ActiveRecord::LockWaitTimeout)
    described_class.perform_now(now: now)
    expect(queued_ids).to eq([order.id])
  end
end
