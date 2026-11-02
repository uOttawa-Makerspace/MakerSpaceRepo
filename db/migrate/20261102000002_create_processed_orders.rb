# The inbox of payment-provider orders the site has to apply: the webhook stores the verified body here and
# answers at once, and a job applies it (retrying until it succeeds), so a delivery is never lost to a Shopify or
# database hiccup while the job runs, and an order is applied once. (provider, provider_ref) is the key, inserted
# with INSERT ... ON CONFLICT DO NOTHING: provider "shopify", provider_ref the Shopify order id (the cash-locker
# fulfilment of an order is a separate unit of work and carries the suffix "/fulfilled").
# status: received (to apply), applied, or failed (retries exhausted; staff re-run it). attempts counts the
# applications tried, last_error is the error class and a short message of the last failed one (no SQL values, no
# personal data). payload is the webhook body as received, so it holds the customer data Shopify sends: it is read
# only by the application job.
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
      t.timestamps

      t.index %i[provider provider_ref], unique: true
      t.index :status
      t.check_constraint "status IN ('received', 'applied', 'failed')", name: "processed_orders_status_check"
    end
  end
end
