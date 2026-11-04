require Rails.root.join("lib/concurrent_index_builder")

# One card row per card number, enforced by the database. The model-level
# uniqueness check cannot prevent two concurrent requests from inserting the same
# new number. The index is case-sensitive (card numbers are stored as the readers
# send them) and built CONCURRENTLY, so writes to rfids are not blocked. A NULL
# card number is allowed any number of times.
#
# The build fails if duplicate card numbers exist; resolve them first.
class AddUniqueIndexToRfidsCardNumber < ActiveRecord::Migration[8.1]
  include ConcurrentIndexBuilder
  disable_ddl_transaction!

  INDEX_NAME = "index_rfids_on_card_number"

  def up
    add_index_concurrently :rfids, :card_number, name: INDEX_NAME, unique: true
  end

  def down
    remove_index :rfids, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
