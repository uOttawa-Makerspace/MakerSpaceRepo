# Ledger of payment-provider orders whose webhook has been applied, so a repeated delivery of the same
# order applies nothing a second time. (provider, provider_ref) is the idempotency key, claimed with
# INSERT ... ON CONFLICT DO NOTHING; provider is "shopify" and provider_ref the Shopify order id.
# The table is named after the first provider; a later provider-agnostic ledger can reuse the key columns.
# No backfill: orders paid before this table existed carry no record. No PII: the order name is Shopify's
# "#1042", for staff reconciliation.
class CreateShopifyOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :shopify_orders do |t|
      t.string :provider, null: false, default: "shopify"
      t.string :provider_ref, null: false
      t.string :topic, null: false
      t.string :order_name
      t.timestamps

      t.index %i[provider provider_ref], unique: true
    end
  end
end
