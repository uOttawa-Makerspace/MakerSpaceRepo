# Records who last edited an event (events.updated_by_id), next to created_by_id, which keeps the
# original creator. Existing rows get no editor (NULL): nothing is backfilled and created_by_id is not
# touched. The key matches created_by_id's: a user who still edits or created an event cannot be
# deleted out from under it, and no event is ever deleted with a user.
#
# down removes the column only while it holds nothing, because the editors exist nowhere else.
# Otherwise it stops, naming the count, and changes nothing.
class AddUpdatedByToEvents < ActiveRecord::Migration[8.1]
  def up
    add_reference :events, :updated_by, foreign_key: { to_table: :users }
  end

  def down
    recorded = select_value("SELECT COUNT(*) FROM events WHERE updated_by_id IS NOT NULL").to_i
    if recorded.positive?
      raise ActiveRecord::IrreversibleMigration,
            "Not going down: #{recorded} events record who last edited them, which exists nowhere else. Copy it elsewhere first."
    end

    remove_reference :events, :updated_by, foreign_key: { to_table: :users }
  end
end
