# frozen_string_literal: true

require "rails_helper"

# The test fake (spec/support/payments/fake_adapter.rb) keeps the same contract as the Shopify adapter.
RSpec.describe Payments::FakeAdapter do
  let(:adapter) { described_class.new }
  let(:provider_name) { "fake" }

  def checkout_in(state)
    id = adapter.create_checkout(lines: [], reference: Payments::Reference.new(kind: "locker", record_id: 1)).id
    adapter.set_state(id, state) unless state == :open
    id
  end

  def arrange_create; end

  def arrange_create_refused = adapter.refuse_next_create!

  def expect_provider_received(lines:, reference:)
    entry = adapter.checkouts.values.last
    expect([entry.lines, entry.reference]).to eq([lines, reference])
  end

  def arrange_open_checkout(reference)
    paid = adapter.create_checkout(lines: [], reference: reference)
    adapter.set_state(paid.id, :paid)
    adapter.create_checkout(lines: [], reference: reference.with(checkout_id: reference.checkout_id + 1))
    adapter.create_checkout(lines: [], reference: reference)
  end

  def arrange_no_open_checkout(reference)
    gone = adapter.create_checkout(lines: [], reference: reference)
    adapter.set_state(gone.id, :gone)
  end

  def webhook(signature, **fields)
    described_class.signed_request(**fields, signature: { valid: :sign, none: nil, wrong: "0" * 64 }.fetch(signature))
  end

  def unsupported_topic_webhook = described_class.request({ provider_ref: "1" }.to_json, topic: "refund")

  def malformed_webhook = described_class.request("[1, 2]")

  it_behaves_like "a Payments adapter"

  it "rejects a notice without a topic, and a body that is not JSON" do
    expect { adapter.parse_webhook(described_class.request("{}", topic: nil)) }
      .to raise_error(Payments::WebhookRejected) { |e| expect(e.reason).to eq(:unsupported_topic) }
    expect { adapter.parse_webhook(described_class.request("not json")) }
      .to raise_error(Payments::WebhookRejected) { |e| expect(e.reason).to eq(:malformed) }
  end

  it "a cancelled checkout is gone afterwards" do
    id = checkout_in(:open)
    adapter.cancel_checkout(id)
    expect(adapter.checkout_status(id)).to eq(:gone)
    expect(adapter.cancel_checkout(id)).to eq(:gone)
  end

  it "an unknown id is gone" do
    expect(adapter.checkout_status("nope")).to eq(:gone)
    expect(adapter.cancel_checkout("nope")).to eq(:gone)
  end
end
