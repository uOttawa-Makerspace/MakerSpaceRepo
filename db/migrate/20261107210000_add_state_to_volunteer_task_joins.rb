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
# down drops the three columns, the constraint and the indexes. It refuses to run once a join has a recorded
# actor or a state that disagrees with `active` (state is joined exactly when active is true), because that
# means the application has started writing real data into the new columns, which down would destroy.
class AddStateToVolunteerTaskJoins < ActiveRecord::Migration[8.1]
  CHECK_NAME = "volunteer_task_joins_state_check"
  STATES = %w[joined completed left removed].freeze

  DISAGREEING = <<~SQL.squish
    SELECT COUNT(*) FROM volunteer_task_joins
    WHERE state_changed_by_id IS NOT NULL OR (state = 'joined') IS DISTINCT FROM (active IS TRUE)
  SQL

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
    changed = select_value(DISAGREEING).to_i
    if changed.positive?
      raise "#{changed} volunteer_task_joins row(s) have a recorded actor or a state that disagrees with " \
            "active; rolling back would discard that data. Nothing was changed"
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
