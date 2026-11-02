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

  it "keeps the error class and a short message, never SQL" do
    expect(described_class.error_summary(ArgumentError.new("bad thing"))).to eq("ArgumentError: bad thing")
    expect(described_class.error_summary(ActiveRecord::StatementInvalid.new("PG::Error value=secret"))).to eq("ActiveRecord::StatementInvalid")
    expect(described_class.error_summary(ArgumentError.new("x" * 500)).length).to eq(200)
  end

  it "re-runs only a failed order" do
    order, = store
    expect(order.reapply!).to be(false)
    order.update!(status: "failed")
    expect(order.reapply!).to be(true)
    expect(order.reload.status).to eq("received")
  end
end
