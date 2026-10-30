# JOB-01 / JOB-03: two nullable columns, no backfill, no default, no index.
#
# job_orders.shopify_draft_order_fingerprint
#   SHA-256 of the line items the stored Shopify draft order was created with,
#   written in the same UPDATE as shopify_draft_order_id. /pay compares it with
#   the order's current line items and never serves a draft that no longer
#   matches. Rows that already hold a draft id get NULL (a "legacy" draft):
#   /pay replaces such a draft once with one built from the current line items
#   (see JobOrder#checkout_link), so no backfill is needed.
#
# job_order_statuses.reason
#   Why a status row was added, when it is not the normal next step:
#   "owner_change" (the order was changed after its quote and went back to
#   staff) or "invoice_mismatch" (/pay found the invoice out of date). NULL for
#   every existing row and for every ordinary transition.
class AddQuoteIntegrityColumnsToJobOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :job_orders, :shopify_draft_order_fingerprint, :string
    add_column :job_order_statuses, :reason, :string
  end
end
