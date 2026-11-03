# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessedOrder do
  def store(order_id = 5001, topic: "orders/paid")
    described_class.receive!(provider: "shopify", order_id: order_id, topic: topic, payload: { "id" => order_id }, name: "#9")
  end

  it "stores a delivery once: the second one returns the stored row and inserts nothing" do
    first, inserted = store
    again, inserted_again = store
    expect([inserted, inserted_again, again.id]).to eq([true, false, first.id])
    expect(first).to have_attributes(status: "received", attempts: 0, last_error: nil, applied_at: nil, order_name: "#9")
  end

  it "keys the fulfilment of an order apart from its paid delivery" do
    paid, = store
    fulfilled, = store(topic: "orders/fulfilled")
    expect([paid.provider_ref, fulfilled.provider_ref]).to eq(%w[5001 5001/fulfilled])
  end

  it "rejects a status outside received, applied and failed (database check)" do
    order, = store
    expect { order.update_columns(status: "done") }.to raise_error(ActiveRecord::StatementInvalid, /processed_orders_status_check/)
  end

  it "stores the delivery due now" do
    order, = store
    expect(order.next_attempt_at).to be_within(5.seconds).of(Time.current)
  end

  it "keeps the error class and a short message, never SQL" do
    expect(described_class.error_summary(ArgumentError.new("bad thing"))).to eq("ArgumentError: bad thing")
    expect(described_class.error_summary(ActiveRecord::StatementInvalid.new("PG::Error value=secret"))).to eq("ActiveRecord::StatementInvalid")
    expect(described_class.error_summary(ArgumentError.new("x" * 500)).length).to eq(200)
  end

  it "re-runs only a failed order, counting its attempts afresh" do
    order, = store
    expect(order.reapply!).to be(false)
    order.update!(status: "failed", attempts: 10)
    expect(order.reapply!).to be(true)
    expect(order.reload).to have_attributes(status: "received", attempts: 0, reported_at: nil)
    expect(order.next_attempt_at).to be_within(5.seconds).of(Time.current)
  end

  it "does not re-run an order a concurrent run applied after it was loaded as failed" do
    order, = store
    order.update!(status: "failed")
    stale = described_class.find(order.id)
    order.update_columns(status: "applied", applied_at: Time.current) # the concurrent run commits
    expect(stale.reapply!).to be(false)
    expect(order.reload.status).to eq("applied")
  end

  describe "the run that holds the order" do
    let(:reports) { [] }
    let(:token) { (Time.current + described_class::LEASE).floor(6) }
    let(:order) { store.first.tap { |o| o.update_columns(leased_until: token) } }

    before { allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] } }

    it "counts the attempt when it starts, once, and only for the lease it holds" do
      now = Time.current.floor(6)
      attempts, fresh = described_class.start_run!(order.id, token, now: now)
      expect(attempts).to eq(1)
      expect(fresh).to eq(now + described_class::LEASE)
      expect(order.reload.leased_until).to eq(fresh)
      expect(described_class.start_run!(order.id, token)).to be_nil # the original token no longer matches
      expect(described_class.start_run!(order.id, token - 1.minute)).to be_nil
      expect(described_class.start_run!(order.id, nil)).to be_nil
      expect(order.reload.attempts).to eq(1)
    end

    it "does not start on an applied or failed order" do
      order.update_columns(status: "applied")
      expect(described_class.start_run!(order.id, token)).to be_nil
      order.update_columns(status: "failed")
      expect(described_class.start_run!(order.id, token)).to be_nil
      expect(order.reload.attempts).to eq(0)
    end

    it "records a failure without counting the attempt again, gives up the lease and sets the backoff" do
      order.update_columns(attempts: 3)
      described_class.record_failure!(order.id, token, ArgumentError.new("bad"))
      expect(order.reload).to have_attributes(attempts: 3, status: "received", last_error: "ArgumentError: bad", leased_until: nil)
      expect(order.next_attempt_at).to be_within(5.seconds).of(Time.current + described_class.backoff(3))
    end

    it "marks the order failed when the failed run was the last attempt" do
      order.update_columns(attempts: described_class::MAX_ATTEMPTS)
      described_class.record_failure!(order.id, token, ArgumentError.new("bad"))
      expect(order.reload).to have_attributes(status: "failed", leased_until: nil)
    end

    it "changes nothing for a stale run, and reports a warning that carries no order data" do
      order.update_columns(leased_until: token + 1.hour, payload: { "email" => "customer@example.com" })
      error = ArgumentError.new("secret customer@example.com")
      described_class.record_failure!(order.id, token, error)
      expect(order.reload).to have_attributes(last_error: nil, leased_until: token + 1.hour, status: "received")
      reported, opts = reports.sole
      expect(reported).to be_a(ApplyProcessedOrderJob::StaleRunFailed)
      expect(opts[:severity]).to eq(:warning)
      expect(opts[:context]).to include(shopify_order_id: "5001", status: "received", error_class: "ArgumentError")
      expect([reported.message, opts[:context].to_s].join).not_to match(/secret|customer@example\.com/)
    end

    it "reports, and changes nothing, when the order is already applied" do
      order.update_columns(status: "applied", applied_at: Time.current)
      described_class.record_failure!(order.id, token, ArgumentError.new("bad"))
      expect(order.reload).to have_attributes(status: "applied", last_error: nil)
      expect(reports.sole.last[:context]).to include(status: "applied")
    end
  end
end
