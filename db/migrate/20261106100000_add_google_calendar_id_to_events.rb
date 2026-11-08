# Records which Google calendar currently holds each event's Google copy, so the push, move and
# delete jobs act on where the copy really is instead of guessing from the event's current space.
#
# Up adds events.google_calendar_id (string, nullable) unless it exists. Nothing is backfilled:
# an empty value means "the calendar of the event's space", which is what the app assumed
# before. Down drops the column. This loses nothing: the column is created by this migration
# and is written only by the Google jobs. No existing column or row is read, changed or deleted
# by either direction.
class AddGoogleCalendarIdToEvents < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:events, :google_calendar_id)

    transaction do
      execute "SET LOCAL lock_timeout = '3s'"
      add_column :events, :google_calendar_id, :string
    end
  end

  def down
    return unless column_exists?(:events, :google_calendar_id)

    transaction do
      execute "SET LOCAL lock_timeout = '3s'"
      remove_column :events, :google_calendar_id
    end
  end
end
