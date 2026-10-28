# frozen_string_literal: true

require "rails_helper"

# Stripe -> locker activation (config/initializers/stripe.rb): a paid Checkout
# Session whose client_reference_id is "locker-rental-<id>" calls
# LockerRental#auto_assign. Both event types are subscribed with the same body.
# Events go through the real StripeEvent engine at /stripe/webhooks, signed with
# StripeEvent.signing_secret exactly as Stripe::Webhook::Signature verifies them
# (header `Stripe-Signature: t=<ts>,v1=<HMAC-SHA256 hex of "<ts>.<body>">`).
RSpec.describe "Stripe webhook: locker rental activation", type: :request do
  include ActiveSupport::Testing::TimeHelpers


  def stripe_post(type, object, signed: true, secret: StripeEvent.signing_secret)
    payload = { id: "evt_#{SecureRandom.hex(4)}", object: "event", type: type, data: { object: object } }.to_json
    headers = { "CONTENT_TYPE" => "application/json" }
    if signed
      ts = Time.now
      sig = Stripe::Webhook::Signature.compute_signature(ts, payload, secret)
      headers["Stripe-Signature"] = "t=#{ts.to_i},v1=#{sig}"
    end
    perform_enqueued_jobs { post "/stripe/webhooks", params: payload, headers: headers }
  end

  def session(rental_ref, payment_status: "paid")
    { id: "cs_#{SecureRandom.hex(3)}", object: "checkout.session", payment_status: payment_status,
      client_reference_id: rental_ref }
  end

  let(:frozen) { Time.utc(2026, 10, 20, 12) }
  let!(:rental) { create(:locker_rental, :await_payment) }
  let!(:other_rental) { create(:locker_rental, :await_payment) }

  before do
    block_external_http!
    rental.update_column(:owned_until, nil)
    ActionMailer::Base.deliveries.clear
  end

  def snapshot(r)
    r.reload.slice(:state, :locker_id, :owned_until, :paid_at, :decided_by_id)
  end

  %w[checkout.session.completed checkout.session.async_payment_succeeded].each do |event_type|
    describe event_type do
      it "activates the referenced await_payment rental: state, same locker, default owned_until, paid_at, assigned mail" do
        locker_before = rental.locker_id
        other_before = snapshot(other_rental)

        travel_to(frozen) { stripe_post(event_type, session("locker-rental-#{rental.id}")) }

        expect(response).to have_http_status(:ok)
        rental.reload
        expect(rental.state).to eq("active")
        expect(rental.locker_id).to eq(locker_before)
        expect(rental.owned_until.utc.iso8601(6)).to eq("2026-12-31T23:59:59.999999Z")
        expect(rental.paid_at).to eq(frozen)
        expect(snapshot(other_rental)).to eq(other_before)
        expect(other_rental.state).to eq("await_payment")

        expect(ActionMailer::Base.deliveries.size).to eq(1)
        mail = ActionMailer::Base.deliveries.first
        expect(mail.to).to eq([rental.rented_by.email])
        expect(mail.subject).to eq("Locker #{rental.locker.specifier} has been assigned for you")
      end

      it "keeps a pre-set owned_until" do
        owned = 20.days.from_now.change(usec: 0)
        rental.update_column(:owned_until, owned)
        stripe_post(event_type, session("locker-rental-#{rental.id}"))
        expect(rental.reload.state).to eq("active")
        expect(rental.owned_until).to eq(owned)
      end

      it "does nothing for an unpaid session (payment_status unpaid)" do
        before = snapshot(rental)
        expect { stripe_post(event_type, session("locker-rental-#{rental.id}", payment_status: "unpaid")) }
          .not_to change { [LockerRental.where(state: "active").count, ActionMailer::Base.deliveries.size] }
        expect(response).to have_http_status(:ok)
        expect(snapshot(rental)).to eq(before)
        expect(rental.state).to eq("await_payment")
      end

      it "does nothing for no_payment_required" do
        stripe_post(event_type, session("locker-rental-#{rental.id}", payment_status: "no_payment_required"))
        expect(response).to have_http_status(:ok)
        expect(rental.reload.state).to eq("await_payment")
        expect(rental.paid_at).to be_nil
      end

      it "does nothing for another reference (job order / shop order), touching no rental" do
        before = [snapshot(rental), snapshot(other_rental)]
        stripe_post(event_type, session("job-order-#{rental.id}"))
        expect(response).to have_http_status(:ok)
        stripe_post(event_type, session("order-#{rental.id}"))
        expect(response).to have_http_status(:ok)
        expect([snapshot(rental), snapshot(other_rental)]).to eq(before)
        expect(ActionMailer::Base.deliveries).to be_empty
      end

      it "answers 200 and changes nothing for an unknown rental id" do
        before = [snapshot(rental), snapshot(other_rental)]
        stripe_post(event_type, session("locker-rental-999999999"))
        expect(response).to have_http_status(:ok)
        expect([snapshot(rental), snapshot(other_rental)]).to eq(before)
        expect(ActionMailer::Base.deliveries).to be_empty
      end

      it "only affects the rental whose id is in the reference" do
        stripe_post(event_type, session("locker-rental-#{other_rental.id}"))
        expect(other_rental.reload.state).to eq("active")
        expect(rental.reload.state).to eq("await_payment")
      end

      it "rejects a bad signature with 400 and changes nothing" do
        before = snapshot(rental)
        stripe_post(event_type, session("locker-rental-#{rental.id}"), secret: "whsec_wrong")
        expect(response).to have_http_status(:bad_request)
        stripe_post(event_type, session("locker-rental-#{rental.id}"), signed: false)
        expect(response).to have_http_status(:bad_request)
        expect(snapshot(rental)).to eq(before)
        expect(rental.state).to eq("await_payment")
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end
  end

  it "does not react to other Stripe event types carrying a locker reference" do
    stripe_post("checkout.session.expired", session("locker-rental-#{rental.id}"))
    expect(response).to have_http_status(:ok)
    expect(rental.reload.state).to eq("await_payment")
  end

  it "replay of an already active rental only re-stamps paid_at and sends no second mail" do
    travel_to(frozen) { stripe_post("checkout.session.completed", session("locker-rental-#{rental.id}")) }
    ActionMailer::Base.deliveries.clear
    travel_to(frozen + 1.hour) { stripe_post("checkout.session.async_payment_succeeded", session("locker-rental-#{rental.id}")) }
    expect(response).to have_http_status(:ok)
    expect(rental.reload.state).to eq("active")
    expect(rental.paid_at).to eq(frozen + 1.hour)
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
