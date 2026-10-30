# JOB-01 / JOB-03: two nullable columns, no backfill, no default, no index.
#
# job_orders.shopify_draft_order_fingerprint
#   JobOrder#quote_fingerprint of the quote the stored Shopify draft order was
#   created from, written in the same UPDATE as shopify_draft_order_id: the
#   SHA-256 of the sorted [task id, component, amount] triples
#     [task id, "service", fee]
#     [task id, "parts", price x quantity]   (only when both are positive)
#     [task id, "option:<job_option id>", fee]
#     [0, "line_item:<job_quote_line_item id>", price]
#   with amounts as 2-decimal strings and no display titles. /pay serves the
#   draft only while it matches (JobOrder#draft_order_current?). Rows that
#   already hold a draft id get NULL (a "legacy" draft): /pay replaces such a
#   draft once with one built from the current quote (see
#   JobOrder#checkout_link), so no backfill is needed.
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
