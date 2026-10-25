# frozen_string_literal: true

require "rails_helper"

# The job-order branches of the Stripe event handlers in
# config/initializers/stripe.rb (D-J30). The initializer's own comment says
# "We don't use stripe anymore ... these callbacks probably do not work
# anymore"; this pins what they do TODAY.
#
# The handlers are invoked with constructed Stripe::Event objects through the
# StripeEvent notification bus (the signature-checked HTTP endpoint is pinned in
# shop_orders_paid_webhook_spec.rb). No Stripe API call is made by these
# branches, so nothing needs stubbing beyond the events themselves.

RSpec.describe "Stripe job-order event handlers", type: :request do
  let(:owner) { create(:user, :regular_user) }

  before do
    seed_job_statuses!
    ActionMailer::Base.deliveries.clear
  end

  def stripe_event(type, session_attrs)
    Stripe::Event.construct_from(
      id: "evt_#{SecureRandom.hex(4)}", object: "event", type: type,
      data: { object: { id: "cs_test_1", object: "checkout.session", payment_status: "paid" }.merge(session_attrs) }
    )
  end

  def fire(type, session_attrs)
    StripeEvent.instrument(stripe_event(type, session_attrs))
  end

  def order_with_status!(status_key, legacy_quote: false)
    order = make_job_order!(owner: owner, status_key: status_key)
    order.update!(job_order_quote: JobOrderQuote.create!(service_fee: 10)) if legacy_quote
    order
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  %w[checkout.session.completed checkout.session.async_payment_succeeded].each do |event_type|
    describe event_type do
      it "marks an order WITH a legacy job_order_quote as paid, stores the Stripe id and delivers the pickup mail" do
        order = order_with_status!(:completed, legacy_quote: true)
        fire(event_type, client_reference_id: "job-order-#{order.id}")

        expect(status_names(order)).to eq(["Completed (Waiting for Payment)", "Paid (Waiting for Pick-Up)"])
        expect(order.job_order_statuses.last.user).to eq(owner)
        expect(order.job_order_quote.reload.stripe_transaction_id).to eq("cs_test_1")
        expect(deliveries.size).to eq(1)
        expect(deliveries.last.to).to eq([owner.email])
        expect(deliveries.last.subject).to eq("Your Job Order ##{order.id} is now ready for pickup")
      end

      # WART(D-J30): no idempotency guard: a replay appends another PAID row and mails again
      it "appends another PAID row and mail on a replay" do
        order = order_with_status!(:completed, legacy_quote: true)
        2.times { fire(event_type, client_reference_id: "job-order-#{order.id}") }

        expect(status_names(order).count("Paid (Waiting for Pick-Up)")).to eq(2)
        expect(deliveries.size).to eq(2)
      end

      # WART(D-J30): no state guard: even a Draft order is flipped to PAID
      it "marks a Draft order as paid as well" do
        order = order_with_status!(:draft, legacy_quote: true)
        fire(event_type, client_reference_id: "job-order-#{order.id}")
        expect(status_names(order)).to eq(["Draft", "Paid (Waiting for Pick-Up)"])
      end

      # WART(D-J30): new-style orders have no legacy job_order_quote; the PAID row
      # is written, then `jo.job_order_quote.update` raises before the mail goes
      # out, so Stripe's retries each add one more PAID row.
      it "raises NoMethodError AFTER writing the PAID row for an order without a legacy quote, and a retry duplicates the row" do
        order = order_with_status!(:completed)

        expect { fire(event_type, client_reference_id: "job-order-#{order.id}") }
          .to raise_error(NoMethodError, /update/)
        expect(status_names(order)).to eq(["Completed (Waiting for Payment)", "Paid (Waiting for Pick-Up)"])
        expect(deliveries).to be_empty

        expect { fire(event_type, client_reference_id: "job-order-#{order.id}") }.to raise_error(NoMethodError)
        expect(status_names(order).count("Paid (Waiting for Pick-Up)")).to eq(2)
        expect(deliveries).to be_empty
      end

      it "ignores sessions that are not paid" do
        order = order_with_status!(:completed, legacy_quote: true)
        fire(event_type, client_reference_id: "job-order-#{order.id}", payment_status: "unpaid")
        expect(status_names(order)).to eq(["Completed (Waiting for Payment)"])
        expect(deliveries).to be_empty
      end

      it "does nothing for an unknown job order id" do
        expect { fire(event_type, client_reference_id: "job-order-99999999") }
          .not_to change { [JobOrderStatus.count, deliveries.size] }
      end
    end
  end

  describe "checkout.session.async_payment_failed" do
    # WART(D-J30): the guard is inverted: the failure mail is only sent when the
    # session reports payment_status "paid", never for a genuinely failed payment.
    it "sends no failure mail for an unpaid (failed) session" do
      order = order_with_status!(:completed)
      fire("checkout.session.async_payment_failed",
           client_reference_id: "job-order-#{order.id}", payment_status: "unpaid")
      expect(deliveries).to be_empty
    end

    it "sends the failure mail only when the session claims to be paid" do
      order = order_with_status!(:completed)
      fire("checkout.session.async_payment_failed", client_reference_id: "job-order-#{order.id}")

      expect(deliveries.size).to eq(1)
      expect(deliveries.last.to).to eq([owner.email])
      expect(deliveries.last.subject).to eq("Your Job Order Payment has failed for Order ##{order.id}")
      expect(status_names(order)).to eq(["Completed (Waiting for Payment)"]) # state untouched
    end

    it "does nothing for an unknown job order" do
      expect { fire("checkout.session.async_payment_failed", client_reference_id: "job-order-99999999") }
        .not_to(change { deliveries.size })
    end
  end
end
