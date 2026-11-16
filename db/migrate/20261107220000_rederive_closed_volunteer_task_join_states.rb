# Joins closed after the state column was added but before the code that writes state shipped keep the state
# 'joined' with active false (the old code only cleared active). This step gives them the state the backfill
# rules would have: an approved request for the same user and task gives completed, anything else removed. The
# time of the change is the row's updated_at and the actor stays NULL (it was never recorded).
#
# Every row changed is recorded first, with its state and change time before, so down restores exactly those
# rows. The record table is kept when this migration is rolled back (it is the undo, and nothing is lost by
# keeping it); a second run records and restores only rows that are drifted again.
class RederiveClosedVolunteerTaskJoinStates < ActiveRecord::Migration[8.1]
  def up
    create_table :volunteer_task_join_state_changes, if_not_exists: true do |t|
      t.bigint :volunteer_task_join_id, null: false
      t.string :old_state, null: false
      t.datetime :old_state_changed_at
      t.string :new_state, null: false
      t.datetime :changed_at, null: false, default: -> { "now()" }
      t.datetime :restored_at
    end
    add_index :volunteer_task_join_state_changes, :volunteer_task_join_id, name: "index_join_state_changes_on_join_id", if_not_exists: true

    execute <<~SQL.squish
      INSERT INTO volunteer_task_join_state_changes (volunteer_task_join_id, old_state, old_state_changed_at, new_state)
      SELECT j.id, j.state, j.state_changed_at,
             CASE WHEN #{approved_request_exists} THEN 'completed' ELSE 'removed' END
      FROM volunteer_task_joins j
      WHERE j.state = 'joined' AND j.active IS NOT TRUE
    SQL

    execute <<~SQL.squish
      UPDATE volunteer_task_joins j
      SET state = c.new_state, state_changed_at = j.updated_at
      FROM volunteer_task_join_state_changes c
      WHERE c.volunteer_task_join_id = j.id AND c.restored_at IS NULL AND j.state = c.old_state
    SQL
  end

  def down
    return unless table_exists?(:volunteer_task_join_state_changes)

    execute <<~SQL.squish
      UPDATE volunteer_task_joins j
      SET state = c.old_state, state_changed_at = c.old_state_changed_at
      FROM volunteer_task_join_state_changes c
      WHERE c.volunteer_task_join_id = j.id AND c.restored_at IS NULL
        AND j.state = c.new_state AND j.state_changed_by_id IS NULL
    SQL
    execute "UPDATE volunteer_task_join_state_changes SET restored_at = now() WHERE restored_at IS NULL"
  end

  private

  def approved_request_exists
    <<~SQL.squish
      EXISTS (
        SELECT 1 FROM volunteer_task_requests r
        WHERE r.user_id = j.user_id AND r.volunteer_task_id = j.volunteer_task_id AND r.approval = TRUE
      )
    SQL
  end
end
