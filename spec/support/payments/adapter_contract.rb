# frozen_string_literal: true

# The Payments contract every adapter keeps (Payments::ShopifyAdapter, Payments::FakeAdapter). The including spec
# defines how its provider is put in each state:
#   adapter                                   the adapter under test
#   provider_name                             its PaymentEvent provider
#   checkout_in(state)                        the id of a checkout in :open, :paid, :gone, :stuck (open, cancel
#                                             refused) or :unanswered (the provider does not answer)
#   arrange_create / arrange_create_refused   the provider will accept / refuse the next create
#   expect_provider_received(lines:, reference:)
#   arrange_open_checkout(reference)          a payable checkout carrying reference.checkout_id; returns its Checkout
#   arrange_no_open_checkout(reference)
#   webhook(signature, provider_ref:, reference:, amount:, paid_at:)   a request, signature :valid, :none or :wrong
#   unsupported_topic_webhook                 a signed notice of a kind the adapter does not turn into a payment
#   malformed_webhook                         a signed notice whose body is not a payment notice
RSpec.shared_examples "a Payments adapter" do
  let(:lines) { [{ quantity: 1, title: "Locker", originalUnitPriceWithCurrency: { amount: "10.0", currencyCode: "CAD" } }] }
  let(:reference) { Payments::Reference.new(kind: "locker", record_id: 42, checkout_id: 7) }

  describe "#create_checkout" do
    it "returns the provider's checkout id and pay URL, and sends the lines and the reference" do
      arrange_create
      checkout = adapter.create_checkout(lines: lines, reference: reference)

      expect(checkout).to be_a(Payments::Checkout)
      expect(checkout.id).to be_present
      expect(checkout.pay_url).to start_with("https://")
      expect_provider_received(lines: lines, reference: reference)
    end

    it "raises when the provider refuses" do
      arrange_create_refused
      expect { adapter.create_checkout(lines: lines, reference: reference) }.to raise_error(StandardError)
    end
  end

  describe "#cancel_checkout" do
    {
      open: :cancelled, paid: :already_paid, gone: :gone, stuck: :failed
    }.each do |state, outcome|
      it "answers #{outcome.inspect} for a checkout that is #{state}" do
        expect(adapter.cancel_checkout(checkout_in(state))).to eq(outcome)
      end
    end

    it "raises, never answers an outcome, when the provider does not answer" do
      id = checkout_in(:unanswered)
      expect { adapter.cancel_checkout(id) }.to raise_error(StandardError)
    end
  end

  describe "#checkout_status" do
    { open: :open, stuck: :open, paid: :paid, gone: :gone, unanswered: :unknown }.each do |state, status|
      it "answers #{status.inspect} for a checkout that is #{state}" do
        expect(adapter.checkout_status(checkout_in(state))).to eq(status)
      end
    end
  end

  describe "#find_open_checkout" do
    it "finds the payable checkout made for the reference's checkout id" do
      expected = arrange_open_checkout(reference)
      expect(adapter.find_open_checkout(reference: reference)).to eq(expected)
    end

    it "answers nil when there is none" do
      arrange_no_open_checkout(reference)
      expect(adapter.find_open_checkout(reference: reference)).to be_nil
    end

    it "needs a checkout id" do
      expect { adapter.find_open_checkout(reference: reference.with(checkout_id: nil)) }.to raise_error(ArgumentError)
    end
  end

  describe "#parse_webhook" do
    let(:paid_at) { Time.zone.parse("2026-11-02 14:30:00") }
    let(:event_fields) { { provider_ref: "5001", reference: reference, amount: BigDecimal("12.5"), paid_at: paid_at } }

    it "returns the verified PaymentEvent of a signed request" do
      event = adapter.parse_webhook(webhook(:valid, **event_fields))
      expect(event).to eq(Payments::PaymentEvent.new(provider: provider_name, **event_fields))
    end

    it "rejects a request without a signature" do
      expect { adapter.parse_webhook(webhook(:none, **event_fields)) }
        .to raise_error(Payments::WebhookRejected) { |e| expect(e.reason).to eq(:unsigned) }
    end

    it "rejects a request whose signature does not match" do
      expect { adapter.parse_webhook(webhook(:wrong, **event_fields)) }
        .to raise_error(Payments::WebhookRejected) { |e| expect(e.reason).to eq(:bad_signature) }
    end

    it "rejects a signed notice it does not turn into a payment" do
      expect { adapter.parse_webhook(unsupported_topic_webhook) }
        .to raise_error(Payments::WebhookRejected) { |e| expect(e.reason).to eq(:unsupported_topic) }
    end

    it "rejects a signed body that is not a payment notice" do
      expect { adapter.parse_webhook(malformed_webhook) }
        .to raise_error(Payments::WebhookRejected) { |e| expect(e.reason).to eq(:malformed) }
    end
  end
end
