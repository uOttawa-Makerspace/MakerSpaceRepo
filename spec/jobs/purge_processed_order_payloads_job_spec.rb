# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeProcessedOrderPayloadsJob, type: :job do
  let(:now) { Time.zone.local(2026, 11, 3, 12, 0, 0) }
  let(:body) { { "id" => 1, "email" => "x@example.com" } }

  def stored(ref, status:, applied_at: nil)
    order, = ProcessedOrder.receive!(provider: "shopify", order_id: ref, topic: "orders/paid", payload: body)
    order.update_columns(status: status, applied_at: applied_at)
    order
  end

  def run = ProcessedOrder.purge_payloads!(now: now)

  it "blanks an applied order older than the retention and keeps the row" do
    order = stored(1, status: "applied", applied_at: now - ProcessedOrder::PAYLOAD_RETENTION - 1.minute)
    expect(run).to eq(1)
    expect(order.reload.payload).to eq({})
    expect(order.status).to eq("applied")
  end

  it "leaves an applied order inside the retention alone" do
    order = stored(1, status: "applied", applied_at: now - ProcessedOrder::PAYLOAD_RETENTION + 1.minute)
    expect(run).to eq(0)
    expect(order.reload.payload).to eq(body)
  end

  it "never touches received or failed orders, however old" do
    old = now - 1.year
    received = stored(1, status: "received", applied_at: old)
    failed = stored(2, status: "failed", applied_at: old)
    expect(run).to eq(0)
    expect([received, failed].map { |o| o.reload.payload }).to eq([body, body])
  end

  it "changes nothing on a second run" do
    order = stored(1, status: "applied", applied_at: now - 100.days)
    run
    stamp = order.reload.updated_at
    expect(run).to eq(0)
    expect(order.reload.updated_at).to eq(stamp)
  end

  it "works through more rows than one batch" do
    stub_const("ProcessedOrder::BATCH", 2)
    orders = (1..5).map { |i| stored(i, status: "applied", applied_at: now - 100.days) }
    expect(run).to eq(5)
    expect(orders.map { |o| o.reload.payload }).to all(eq({}))
  end

  it "is a plain job run that purges" do
    order = stored(1, status: "applied", applied_at: 100.days.ago)
    described_class.perform_now
    expect(order.reload.payload).to eq({})
  end

  it "is scheduled daily in production and staging" do
    config = YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true)
    %w[production staging].each do |env|
      expect(config.dig(env, "purge_processed_order_payloads", "class")).to eq("PurgeProcessedOrderPayloadsJob")
      expect(config.dig(env, "purge_processed_order_payloads", "schedule")).to eq("every day at 4am")
    end
  end
end
