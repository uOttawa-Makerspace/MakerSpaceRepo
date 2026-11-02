# Payment-provider orders the site has already applied, so a repeated or late webhook delivery of the
# same order applies nothing a second time. (provider, provider_ref) is the key, claimed with
# INSERT ... ON CONFLICT DO NOTHING; e.g. provider "shopify" and provider_ref the Shopify order id.
# Holds no amounts: it is not the payments ledger. No backfill: orders applied before this table
# existed carry no record. No PII: order_name is the provider's display name (Shopify's "#1042").
class CreateProcessedOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_orders do |t|
      t.string :provider, null: false
      t.string :provider_ref, null: false
      t.string :topic, null: false
      t.string :order_name
      t.timestamps

      t.index %i[provider provider_ref], unique: true
    end
  end
end
