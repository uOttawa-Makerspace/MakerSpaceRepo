require Rails.root.join("lib/concurrent_index_builder")
require Rails.root.join("lib/learning_module_track_merge")

# One learning_module_tracks row per (user, learning module): duplicates, which
# the model-level uniqueness check could not prevent under concurrent requests,
# are merged into the oldest row of each group. Nothing else references a track.
#
# The merge rule (status, dates, SCORM state) is LearningModuleTrackMerge, shared with
# users:merge_duplicates; no completion is ever lost. Every removed row is copied in full
# into learning_module_tracks_merged, with the kept row's values before and after, by the
# same statement that removes it, so down can put the rows back exactly.
#
# The unique index on (user_id, learning_module_id) is built right after the merge,
# CONCURRENTLY, so writes to the table are not blocked. A request can still create a
# duplicate between the merge and the end of the build; the build then fails, leaving
# an INVALID index. That index is dropped, the merge is run again and the build is
# retried once. The plain user_id index is covered by the new one (user_id leads) and
# is dropped.
#
# Safe to run again: once merged there are no groups left, and an existing valid index
# is kept.
class MergeDuplicatesAndAddUniqueIndexToLearningModuleTracks < ActiveRecord::Migration[8.1]
  include ConcurrentIndexBuilder
  disable_ddl_transaction!

  INDEX_NAME = "index_learning_module_tracks_on_user_and_learning_module"
  SOURCE = "20261104000006"

  def up
    create_archive_table
    merge_duplicates
    begin
      add_index_concurrently :learning_module_tracks, %i[user_id learning_module_id], name: INDEX_NAME, unique: true
    rescue ActiveRecord::RecordNotUnique
      raise if @retried

      @retried = true
      say "a duplicate appeared while the index was built; merging again and retrying"
      remove_index :learning_module_tracks, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
      merge_duplicates
      retry
    end
    remove_index :learning_module_tracks, name: "index_learning_module_tracks_on_user_id",
                                          algorithm: :concurrently, if_exists: true
  end

  # Puts back the rows this migration removed, with their ids, and the kept rows' values
  # from before the merge, then the indexes as they were. Raises, changing nothing and keeping
  # the archive, if a removed row cannot be put back or a kept row was edited since the merge.
  def down
    transaction do
      execute "SET LOCAL lock_timeout = '3s'"
      execute "LOCK TABLE learning_module_tracks IN SHARE ROW EXCLUSIVE MODE"
      execute "DROP INDEX IF EXISTS #{INDEX_NAME}"
      result = LearningModuleTrackMerge.restore!(connection, source: SOURCE)
      say "learning_module_tracks: #{result[:restored]} rows put back, #{result[:keepers_restored]} kept rows restored"
    end
    add_index_concurrently :learning_module_tracks, :user_id, name: "index_learning_module_tracks_on_user_id"
  end

  def create_archive_table
    LearningModuleTrackMerge.create_archive_table(connection)
  end

  def merge_duplicates
    report_groups

    transaction do
      # Writes wait for the few milliseconds the merge takes, so a track created meanwhile
      # cannot be removed without having been merged.
      execute "SET LOCAL lock_timeout = '3s'"
      execute "LOCK TABLE learning_module_tracks IN SHARE ROW EXCLUSIVE MODE"
      removed = LearningModuleTrackMerge.merge!(connection, source: SOURCE)
      say "learning_module_tracks: #{removed} duplicate rows merged away"
    end
  end

  private

  def report_groups
    rows = select_rows(<<~SQL.squish)
      SELECT statuses, COUNT(*) FROM (
        SELECT STRING_AGG(COALESCE(status, 'none'), ' + ' ORDER BY status) AS statuses
        FROM learning_module_tracks
        WHERE user_id IS NOT NULL AND learning_module_id IS NOT NULL
        GROUP BY user_id, learning_module_id
        HAVING COUNT(*) > 1
      ) s GROUP BY statuses ORDER BY statuses
    SQL
    rows.each { |statuses, count| say "duplicate groups (#{statuses}): #{count}" }
  end
end
