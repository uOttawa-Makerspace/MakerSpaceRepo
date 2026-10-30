require Rails.root.join("lib/concurrent_index_builder")

# Three of these indexes were in db/schema.rb (dumped from a local database)
# but no migration ever created them, so production lacks them. Names and
# columns are exactly what schema.rb declares. Staging loaded the dumped schema
# and may already have them; the builder keeps a valid one and rebuilds an
# INVALID one.
#
# The composites also lead with the column of a plain single-column index, so
# those are dropped: one index per leading column, and PostgreSQL foreign keys
# need no index. idx_staff_unavail_user_times (in the dumped schema, queried by
# nothing: staff_unavailabilities is only ever looked up by user_id) is dropped
# too and left out of schema.rb.
class AddMissingSpaceAndUnavailabilityIndexes < ActiveRecord::Migration[8.1]
  include ConcurrentIndexBuilder
  disable_ddl_transaction!

  def up
    add_index_concurrently :events, %i[space_id draft], name: "idx_events_on_space_and_draft"
    add_index_concurrently :events, %i[space_id start_time end_time], name: "idx_events_on_space_and_times"
    add_index_concurrently :staff_spaces, %i[space_id user_id], name: "idx_staff_spaces_space_user"

    remove_index :events, name: "index_events_on_space_id", algorithm: :concurrently, if_exists: true
    remove_index :staff_spaces, name: "index_staff_spaces_on_space_id", algorithm: :concurrently, if_exists: true
    # only in databases that loaded the old dumped schema (staging)
    remove_index :staff_unavailabilities, name: "idx_staff_unavail_user_times", algorithm: :concurrently, if_exists: true
  end

  # Reversible except for idx_staff_unavail_user_times, deliberately: it is
  # not part of the schema (nothing queries it), so `up` removes it where it
  # exists (staging) and `down` does not bring it back. Recreating an unused
  # index on every rollback would only reintroduce what `up` removed on purpose.
  def down
    add_index_concurrently :events, :space_id, name: "index_events_on_space_id"
    add_index_concurrently :staff_spaces, :space_id, name: "index_staff_spaces_on_space_id"

    remove_index :events, name: "idx_events_on_space_and_draft", algorithm: :concurrently, if_exists: true
    remove_index :events, name: "idx_events_on_space_and_times", algorithm: :concurrently, if_exists: true
    remove_index :staff_spaces, name: "idx_staff_spaces_space_user", algorithm: :concurrently, if_exists: true
  end
end
