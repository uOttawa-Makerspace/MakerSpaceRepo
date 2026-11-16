# A shadowing shift's Google Calendar event is created by a job that is tried again until Google has it, so the
# pending-changes table can now hold a third kind of change: 'shadow_push', which names a shadowing hour instead of
# an event. Additive: a nullable column, a nullable event_id, a wider action check and an index that also covers the
# new column. No existing row is touched (every existing row has an event_id and no shadowing hour).
# The foreign key removes a waiting change together with the shift it belongs to, which is all it can be then.
# Down refuses to run while shadow_push rows exist, because the old schema cannot hold them; it never deletes them.
class AddShadowingHoursToGoogleCalendarPendingChanges < ActiveRecord::Migration[8.1]
  TABLE = :google_calendar_pending_changes
  OLD_IDENTITY = %i[action event_id google_event_id].freeze
  NEW_IDENTITY = %i[action event_id google_event_id shadowing_hour_id].freeze
  INDEX = "index_google_calendar_pending_changes_identity"

  def up
    add_column TABLE, :shadowing_hour_id, :bigint
    add_foreign_key TABLE, :shadowing_hours, column: :shadowing_hour_id, on_delete: :cascade
    change_column_null TABLE, :event_id, true
    remove_index TABLE, name: INDEX
    add_index TABLE, NEW_IDENTITY, unique: true, nulls_not_distinct: true, name: INDEX
    remove_check_constraint TABLE, name: "google_calendar_pending_changes_action_check"
    add_check_constraint TABLE, "action IN ('push', 'remove', 'shadow_push')", name: "google_calendar_pending_changes_action_check"
    add_check_constraint TABLE,
                         "(action = 'shadow_push' AND shadowing_hour_id IS NOT NULL AND event_id IS NULL) OR " \
                         "(action <> 'shadow_push' AND shadowing_hour_id IS NULL AND event_id IS NOT NULL)",
                         name: "google_calendar_pending_changes_subject_check"
  end

  def down
    waiting = select_value("SELECT COUNT(*) FROM #{TABLE} WHERE action = 'shadow_push'").to_i
    if waiting.positive?
      raise ActiveRecord::IrreversibleMigration,
            "#{waiting} shadowing shift calendar change(s) are still waiting in #{TABLE}; the older schema cannot hold " \
            "them. Let them finish (or have the maintainers approve removing them), then roll back."
    end

    remove_check_constraint TABLE, name: "google_calendar_pending_changes_subject_check"
    remove_check_constraint TABLE, name: "google_calendar_pending_changes_action_check"
    add_check_constraint TABLE, "action IN ('push', 'remove')", name: "google_calendar_pending_changes_action_check"
    remove_index TABLE, name: INDEX
    add_index TABLE, OLD_IDENTITY, unique: true, nulls_not_distinct: true, name: INDEX
    change_column_null TABLE, :event_id, false
    remove_foreign_key TABLE, column: :shadowing_hour_id
    remove_column TABLE, :shadowing_hour_id
  end
end
