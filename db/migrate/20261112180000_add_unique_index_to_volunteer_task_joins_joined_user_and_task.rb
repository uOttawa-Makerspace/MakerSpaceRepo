require Rails.root.join("lib/unique_index_guard")

# A user is joined to a task at most once at a time. The model validation says so, but two simultaneous joins can
# both pass it, so the database now enforces it with a unique index on (task, user) for joined rows only; ended
# rows (completed, left, removed) are history and may repeat.
#
# One pair already has two joined rows. This step ends the newer of the two (the row is kept, with the state
# 'removed', no actor, and active false, the same end state a staff removal gives) and records its state before
# in volunteer_task_join_duplicate_endings, so down puts it back exactly. It changes nothing unless exactly one
# pair has exactly two joined rows; any other duplicate joined rows stop the migration with a message listing
# them, and nothing is changed. Running it again finds no duplicate and changes nothing.
#
# The record table is kept when this migration is rolled back (it is the undo, and nothing is lost by keeping it).
class AddUniqueIndexToVolunteerTaskJoinsJoinedUserAndTask < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_volunteer_task_joins_on_task_and_user_when_joined"
  JOINED = "state = 'joined'"

  def up
    create_record_table
    end_newer_duplicate
    add_unique_index_concurrently :volunteer_task_joins, %i[volunteer_task_id user_id], name: INDEX_NAME, where: JOINED
  end

  def down
    remove_unique_index_concurrently :volunteer_task_joins, name: INDEX_NAME
    return unless table_exists?(:volunteer_task_join_duplicate_endings)

    transaction do
      execute <<~SQL.squish
        UPDATE volunteer_task_joins j
        SET state = e.old_state, active = e.old_active, state_changed_at = e.old_state_changed_at,
            state_changed_by_id = e.old_state_changed_by_id, updated_at = e.old_updated_at
        FROM volunteer_task_join_duplicate_endings e
        WHERE e.volunteer_task_join_id = j.id AND e.restored_at IS NULL AND j.state = e.new_state
      SQL
      execute "UPDATE volunteer_task_join_duplicate_endings SET restored_at = now() WHERE restored_at IS NULL"
    end
  end

  private

  def create_record_table
    create_table :volunteer_task_join_duplicate_endings, if_not_exists: true do |t|
      t.bigint :volunteer_task_join_id, null: false
      t.bigint :kept_join_id, null: false
      t.string :old_state, null: false
      t.boolean :old_active
      t.datetime :old_state_changed_at
      t.bigint :old_state_changed_by_id
      t.datetime :old_updated_at, null: false
      t.string :new_state, null: false
      t.datetime :ended_at, null: false, default: -> { "now()" }
      t.datetime :restored_at
    end
    add_index :volunteer_task_join_duplicate_endings, :volunteer_task_join_id,
              name: "index_join_duplicate_endings_on_join_id", if_not_exists: true
  end

  def end_newer_duplicate
    groups = joined_duplicate_groups
    return if groups.empty?

    unless groups.size == 1 && groups.first.size == 2
      listing = groups.map { |ids| "ids #{ids.join(',')}" }
      raise UniqueIndexGuard::DuplicatesFound,
            "volunteer_task_joins has joined duplicates other than the one expected pair of two rows. " \
            "Nothing was changed. Resolve these by hand, then run the migration again:\n  #{listing.join("\n  ")}"
    end

    keep, newer = groups.first
    transaction { record_and_end(newer, keep) }
  end

  # Ids of each (task, user) pair with more than one joined row, oldest first (created_at, then id).
  def joined_duplicate_groups
    select_rows(<<~SQL.squish).map { |row| row.first.split(",").map(&:to_i) }
      SELECT string_agg(id::text, ',' ORDER BY created_at, id)
      FROM volunteer_task_joins
      WHERE #{JOINED} AND volunteer_task_id IS NOT NULL AND user_id IS NOT NULL
      GROUP BY volunteer_task_id, user_id
      HAVING count(*) > 1
      ORDER BY min(id)
    SQL
  end

  def record_and_end(newer, keep)
    execute <<~SQL.squish
      INSERT INTO volunteer_task_join_duplicate_endings
        (volunteer_task_join_id, kept_join_id, old_state, old_active, old_state_changed_at,
         old_state_changed_by_id, old_updated_at, new_state)
      SELECT id, #{keep.to_i}, state, active, state_changed_at, state_changed_by_id, updated_at, 'removed'
      FROM volunteer_task_joins WHERE id = #{newer.to_i} AND #{JOINED}
    SQL
    execute <<~SQL.squish
      UPDATE volunteer_task_joins
      SET state = 'removed', active = FALSE, state_changed_at = now(), state_changed_by_id = NULL, updated_at = now()
      WHERE id = #{newer.to_i} AND #{JOINED}
    SQL
  end
end
