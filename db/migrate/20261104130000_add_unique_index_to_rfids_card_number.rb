require Rails.root.join("lib/concurrent_index_builder")

# One card row per card number, enforced by the database. The model-level
# uniqueness check cannot prevent two concurrent requests from inserting the same
# new number. The index is case-sensitive (card numbers are stored as the readers
# send them) and built CONCURRENTLY, so writes to rfids are not blocked. A NULL
# card number is allowed any number of times.
#
# Duplicate card numbers would make the build fail and leave an INVALID index, so
# they are counted first and the migration refuses to run while any exist: they
# are never merged automatically (which row owns the card is a decision for a
# person). An INVALID index of this name left by an earlier failed build is
# dropped and rebuilt by add_index_concurrently.
class AddUniqueIndexToRfidsCardNumber < ActiveRecord::Migration[8.1]
  include ConcurrentIndexBuilder
  disable_ddl_transaction!

  INDEX_NAME = "index_rfids_on_card_number"

  def up
    refuse_duplicates
    add_index_concurrently :rfids, :card_number, name: INDEX_NAME, unique: true
  end

  def down
    remove_index :rfids, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end

  def refuse_duplicates
    count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM (
        SELECT card_number FROM rfids WHERE card_number IS NOT NULL
        GROUP BY card_number HAVING COUNT(*) > 1
      ) duplicated
    SQL
    return if count.zero?

    raise "#{count} card numbers appear on more than one rfids row; resolve those duplicates " \
          "(decide which row keeps the card) before adding the unique index"
  end
end
