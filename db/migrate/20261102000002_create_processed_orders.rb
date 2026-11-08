# The inbox of payment-provider orders the site has to apply: the webhook stores the verified body here and
# answers at once, and a job applies it (retrying until it succeeds), so a delivery is never lost to a Shopify or
# database hiccup while the job runs, and an order is applied once. (provider, provider_ref) is the key, inserted
# with INSERT ... ON CONFLICT DO NOTHING: provider "shopify", provider_ref the Shopify order id (the cash-locker
# fulfilment of an order is a separate unit of work and carries the suffix "/fulfilled").
# status: received (to apply), applied, or failed (retries exhausted; staff re-run it). next_attempt_at is only when
# a received order is next due: the webhook sets it to now, a failed run sets it to the backoff time, a staff re-run
# sets it to now. leased_until is the hand-out: a dispatcher claims a due order by setting it to now plus a lease, the
# job it queues carries that value as its token, and a run that no longer holds it cannot record an outcome; null
# when nobody holds the order. attempts counts the runs that started (a job still waiting in the queue costs
# nothing), last_error is the error class and a short message of the last failed one (no SQL values, no personal
# data); reported_at is when an order that has been due for hours was last reported. payload is the webhook body as
# received, so it holds the customer data Shopify sends: it is read only by the application job, and it is blanked
# to {} 90 days after the order is applied (ProcessedOrder.purge_payloads!); the row stays.
# Holds no amounts of its own: it is not the payments ledger. No backfill: orders applied before this table
# existed carry no record. order_name is the provider's display name (Shopify's "#1042").
class CreateProcessedOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_orders do |t|
      t.string :provider, null: false
      t.string :provider_ref, null: false
      t.string :topic, null: false
      t.string :order_name
      t.jsonb :payload, null: false
      t.string :status, null: false, default: "received"
      t.integer :attempts, null: false, default: 0
      t.string :last_error
      t.datetime :applied_at
      t.datetime :next_attempt_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :leased_until
      t.datetime :reported_at
      t.timestamps

      t.index %i[provider provider_ref], unique: true
      t.index %i[status next_attempt_at]
      t.check_constraint "status IN ('received', 'applied', 'failed')", name: "processed_orders_status_check"
    end
  end
end
