# A volunteer task join gets a state of its own: joined (on the task now), completed (the task's request was
# approved), left (the volunteer removed themselves) or removed (staff removed them). This step is additive:
# it adds the state, when it last changed and who changed it, and copies the old `active` flag into the state.
# `active` is not touched and nothing reads the new columns yet.
#
# Backfill:
# - active is true: joined.
# - otherwise (false, or NULL, which the current readers also treat as not active) with an approved request
#   for the same user and task: completed.
# - any other: removed (the data cannot tell a removal from a leave).
# Closed rows take their updated_at as the time of the change. The actor was never recorded, so it stays NULL.
#
# state_changed_by_id is nullified when the user row is deleted, so a user deletion is never blocked and never
# removes a join.
#
# Joins closed after this migration and before the code that writes state is switched over keep state
# 'joined' (the application still only sets active to false); that code switch re-derives them.
#
# down drops the three columns, the constraint and the indexes. Until the code writes state, every state
# is derived (the default or this backfill), so dropping it loses nothing, even for rows whose active flag
# has changed since. down refuses when a join has a recorded actor (state_changed_by_id) or the state
# 'left', because those exist nowhere else: the actor is lost with the column, and a leave cannot be
# re-derived from active and the requests (the actor is also nullified if that user is deleted).
class AddStateToVolunteerTaskJoins < ActiveRecord::Migration[8.1]
  CHECK_NAME = "volunteer_task_joins_state_check"
  STATES = %w[joined completed left removed].freeze

  UNRECOVERABLE = "SELECT COUNT(*) FROM volunteer_task_joins WHERE state_changed_by_id IS NOT NULL OR state = 'left'"

  def up
    add_column :volunteer_task_joins, :state, :string, null: false, default: "joined"
    add_column :volunteer_task_joins, :state_changed_at, :datetime
    add_column :volunteer_task_joins, :state_changed_by_id, :bigint
    add_check_constraint :volunteer_task_joins, "state IN (#{STATES.map { |s| "'#{s}'" }.join(', ')})", name: CHECK_NAME
    add_foreign_key :volunteer_task_joins, :users, column: :state_changed_by_id, on_delete: :nullify
    add_index :volunteer_task_joins, :state_changed_by_id
    add_index :volunteer_task_joins, %i[volunteer_task_id state]

    execute <<~SQL.squish
      UPDATE volunteer_task_joins j
      SET state = CASE
            WHEN EXISTS (
              SELECT 1 FROM volunteer_task_requests r
              WHERE r.user_id = j.user_id AND r.volunteer_task_id = j.volunteer_task_id AND r.approval = TRUE
            ) THEN 'completed'
            ELSE 'removed'
          END,
          state_changed_at = j.updated_at
      WHERE j.active IS NOT TRUE
    SQL
  end

  def down
    recorded = select_value(UNRECOVERABLE).to_i
    if recorded.positive?
      raise "#{recorded} volunteer_task_joins row(s) have a recorded state_changed_by_id or the state " \
            "'left', which exist nowhere else; rolling back would discard them. Nothing was changed"
    end

    remove_index :volunteer_task_joins, %i[volunteer_task_id state]
    remove_index :volunteer_task_joins, :state_changed_by_id
    remove_foreign_key :volunteer_task_joins, column: :state_changed_by_id
    remove_check_constraint :volunteer_task_joins, name: CHECK_NAME
    remove_column :volunteer_task_joins, :state_changed_by_id
    remove_column :volunteer_task_joins, :state_changed_at
    remove_column :volunteer_task_joins, :state
  end
end
