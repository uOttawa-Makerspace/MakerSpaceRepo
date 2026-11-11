require Rails.root.join("lib/unique_index_guard")

# A volunteer's pending (not yet reviewed) hour for one task, day and length exists at most once. Until now nothing
# stopped a double click or a resubmitted form from storing it twice. If identical pending hours already exist the
# migration stops and lists the rows; it never changes or removes rows.
class AddUniqueIndexToPendingVolunteerHours < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_volunteer_hours_on_pending_submission"

  def up
    add_unique_index_concurrently :volunteer_hours,
                                  %i[user_id volunteer_task_id date_of_task total_time],
                                  name: INDEX_NAME,
                                  where: "approval IS NULL"
  end

  def down
    remove_unique_index_concurrently :volunteer_hours, name: INDEX_NAME
  end
end
