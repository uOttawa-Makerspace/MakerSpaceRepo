require Rails.root.join("lib/unique_index_guard")

# A key has at most one open transaction (one without a return date). Closed transactions are the audit
# history and may repeat the key freely. If a key already has several open transactions the migration stops and
# lists them; it never changes or removes rows.
class AddUniqueIndexToKeyTransactionsOpenKey < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_key_transactions_on_key_id_open"

  def up
    add_unique_index_concurrently :key_transactions, :key_id, name: INDEX_NAME, where: "return_date IS NULL"
  end

  def down
    remove_unique_index_concurrently :key_transactions, name: INDEX_NAME
  end
end
