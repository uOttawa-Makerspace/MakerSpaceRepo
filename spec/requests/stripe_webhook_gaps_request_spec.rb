# frozen_string_literal: true

require "rails_helper"

# Chunk 18: gaps in the Stripe engine mount coverage. Unsigned and mis-signed
# events are pinned in shop_orders_paid_webhook_spec.rb, the job-order/locker
# handlers in stripe_job_order_handlers_spec.rb. Here: verbs, replay tolerance,
# tampered bodies, and that no session/CSRF is involved.
RSpec.describe "Stripe webhook mount (gaps)", type: :request do
  let(:secret) { StripeEvent.signing_secret }
  let(:payload) do
    { id: "evt_1", object: "event", type: "customer.created", data: { object: { id: "cus_1" } } }.to_json
  end

  def signed_headers(body, timestamp: Time.now, signing_secret: secret)
    sig = Stripe::Webhook::Signature.compute_signature(timestamp, body, signing_secret)
    { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => "t=#{timestamp.to_i},v1=#{sig}" }
  end

  it "has a signing secret configured in the test environment" do
    expect(secret).to be_present
  end

  it "accepts a signed event with no session at all, even with forgery protection on (the engine skips auth and CSRF)" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post "/stripe/webhooks", params: payload, headers: signed_headers(payload)
    expect(response).to have_http_status(:ok)
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "only routes POST (GET is a routing 404)" do
    get "/stripe/webhooks"
    expect(response).to have_http_status(:not_found)
  end

  it "rejects a replayed signature outside the 5 minute tolerance with 400" do
    post "/stripe/webhooks", params: payload, headers: signed_headers(payload, timestamp: 1.hour.ago)
    expect(response).to have_http_status(:bad_request)
  end

  it "rejects a body that differs from the signed one with 400 and runs no handler" do
    headers = signed_headers(payload)
    tampered = payload.sub("cus_1", "cus_evil")
    expect(StripeEvent).not_to receive(:instrument)
    post "/stripe/webhooks", params: tampered, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it "rejects a signature header without a v1 part with 400" do
    post "/stripe/webhooks", params: payload,
         headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => "t=#{Time.now.to_i}" }
    expect(response).to have_http_status(:bad_request)
  end

  it "rejects a correctly signed body that is not JSON with 400" do
    body = "not json"
    post "/stripe/webhooks", params: body, headers: signed_headers(body)
    expect(response).to have_http_status(:bad_request)
  end
end
