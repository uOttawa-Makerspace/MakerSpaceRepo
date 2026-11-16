# One row per Google Calendar change that has been asked for and not yet confirmed: a push of an event's current
# state, or the removal of a destroyed event's Google copy. The row is written before the job is queued and removed
# by the job once Google has the change, so a change whose job could not be queued is found again by the resend job.
# Additive: no existing table or row is touched; down drops the new table only.
class CreateGoogleCalendarPendingChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :google_calendar_pending_changes do |t|
      t.string :action, null: false
      t.bigint :event_id, null: false
      t.string :google_event_id
      t.string :calendar_id
      t.integer :attempts, null: false, default: 0
      t.timestamps
    end
    # A push is one row per event; a removal is one row per Google copy (an event can be unpublished twice).
    add_index :google_calendar_pending_changes, %i[action event_id google_event_id], unique: true, nulls_not_distinct: true,
                                                   name: "index_google_calendar_pending_changes_identity"
    add_check_constraint :google_calendar_pending_changes, "action IN ('push', 'remove')",
                         name: "google_calendar_pending_changes_action_check"
  end
end
