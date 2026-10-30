# These four indexes were in db/schema.rb (dumped from a local database) but no
# migration ever created them, so production lacks them. Names and columns are
# exactly what schema.rb already declares. if_not_exists because staging loaded
# the dumped schema and may already have some.
class AddMissingSpaceAndUnavailabilityIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :events, %i[space_id draft], name: "idx_events_on_space_and_draft", algorithm: :concurrently, if_not_exists: true
    add_index :events, %i[space_id start_time end_time], name: "idx_events_on_space_and_times", algorithm: :concurrently, if_not_exists: true
    add_index :staff_spaces, %i[space_id user_id], name: "idx_staff_spaces_space_user", algorithm: :concurrently, if_not_exists: true
    add_index :staff_unavailabilities, %i[user_id start_time end_time], name: "idx_staff_unavail_user_times", algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :events, name: "idx_events_on_space_and_draft", algorithm: :concurrently, if_exists: true
    remove_index :events, name: "idx_events_on_space_and_times", algorithm: :concurrently, if_exists: true
    remove_index :staff_spaces, name: "idx_staff_spaces_space_user", algorithm: :concurrently, if_exists: true
    remove_index :staff_unavailabilities, name: "idx_staff_unavail_user_times", algorithm: :concurrently, if_exists: true
  end
end
