# frozen_string_literal: true

module Payments
  # An in-memory payment provider for specs: it keeps the Payments contract (the same shared examples as
  # Payments::ShopifyAdapter, spec/support/payments/adapter_contract.rb) without any HTTP.
  #
  # A checkout is :open after create_checkout. Specs move it with #set_state:
  #   :paid        paid (cancel answers :already_paid)
  #   :gone        no longer exists
  #   :stuck       open, but the provider refuses to cancel it (:failed)
  #   :unanswered  the provider does not answer (status :unknown; cancel raises)
  # #refuse_next_create! makes the next create_checkout raise. Webhooks are JSON bodies signed with SECRET
  # (#signed_request builds one).
  class FakeAdapter
    PROVIDER = "fake"
    SECRET = "fake-payments-secret"
    SIGNATURE_HEADER = "HTTP_X_FAKE_PAYMENTS_SIGNATURE"
    OPEN_STATES = %i[open stuck].freeze
    STATUS = { open: :open, stuck: :open, paid: :paid, gone: :gone, unanswered: :unknown }.freeze
    CANCEL = { stuck: :failed, paid: :already_paid, gone: :gone }.freeze

    class Unanswered < StandardError; end

    Entry = Struct.new(:id, :lines, :reference, :state, :pay_url, keyword_init: true)

    attr_reader :checkouts

    def initialize
      @checkouts = {}
      @sequence = 0
      @refuse_next_create = false
    end

    def create_checkout(lines:, reference:)
      if @refuse_next_create
        @refuse_next_create = false
        raise "the fake provider refused the checkout"
      end

      id = "fake-checkout-#{@sequence += 1}"
      @checkouts[id] = Entry.new(id: id, lines: lines, reference: reference, state: :open,
                                 pay_url: "https://pay.example.test/#{id}")
      Checkout.new(id: id, pay_url: @checkouts[id].pay_url)
    end

    def cancel_checkout(id)
      entry = @checkouts[id]
      return :gone if entry.nil?
      raise Unanswered, "the fake provider did not answer" if entry.state == :unanswered

      return CANCEL.fetch(entry.state) unless entry.state == :open

      entry.state = :gone
      :cancelled
    end

    def checkout_status(id) = STATUS.fetch(@checkouts[id]&.state || :gone)

    def find_open_checkout(reference:)
      raise ArgumentError, "the reference has no checkout id" if reference.checkout_id.blank?

      entry = @checkouts.values.find do |e|
        OPEN_STATES.include?(e.state) && e.reference.checkout_id == reference.checkout_id
      end
      entry && Checkout.new(id: entry.id, pay_url: entry.pay_url)
    end

    def parse_webhook(request)
      signature = request.headers[SIGNATURE_HEADER]
      raise WebhookRejected, :unsigned if signature.blank?
      raise WebhookRejected, :bad_signature unless ActiveSupport::SecurityUtils.secure_compare(signature, self.class.sign(request.raw_post))

      event_from(JSON.parse(request.raw_post))
    end

    # --- spec controls ---

    def set_state(id, state)
      @checkouts.fetch(id).state = state
    end

    def refuse_next_create!
      @refuse_next_create = true
    end

    def self.sign(body) = OpenSSL::HMAC.hexdigest("sha256", SECRET, body)

    # A POST whose JSON body names the event's fields, signed (or with `signature:` instead).
    def self.signed_request(provider_ref:, reference:, amount:, paid_at:, signature: :sign)
      body = { provider_ref: provider_ref, reference: reference.to_h, amount: amount.to_s, paid_at: paid_at.iso8601 }.to_json
      headers = { "CONTENT_TYPE" => "application/json" }
      headers[SIGNATURE_HEADER] = signature == :sign ? sign(body) : signature if signature
      ActionDispatch::Request.new(Rack::MockRequest.env_for("/payments/fake", method: "POST", input: body, **headers))
    end

    private

    def event_from(hook)
      ref = hook["reference"]
      PaymentEvent.new(provider: PROVIDER, provider_ref: hook["provider_ref"],
                       reference: Reference.new(kind: ref["kind"], record_id: ref["record_id"], checkout_id: ref["checkout_id"]),
                       amount: BigDecimal(hook["amount"]), paid_at: Time.zone.parse(hook["paid_at"]))
    end
  end
end
