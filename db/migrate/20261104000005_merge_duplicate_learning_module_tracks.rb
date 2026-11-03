# One learning_module_tracks row per (user, learning module): duplicates, which
# the model-level uniqueness check could not prevent under concurrent requests,
# are merged into the oldest row of each group. Nothing else references a track.
#
# The kept row takes
# - status: Completed if any row in the group is Completed (or the SCORM state
#   kept says so), else In progress if any is, else the most recently updated
#   row's status; a completion is never lost;
# - created_at: the earliest of the group;
# - updated_at: the latest of the group;
# - scorm_state: that of the most recently updated row that has one.
# The other rows of the group are then removed.
#
# Safe to run again: once merged there are no groups left.
class MergeDuplicateLearningModuleTracks < ActiveRecord::Migration[8.1]
  GROUPS = <<~SQL.squish
    SELECT user_id, learning_module_id,
           (ARRAY_AGG(id ORDER BY created_at, id))[1] AS keeper_id,
           MIN(created_at) AS first_created_at,
           MAX(updated_at) AS last_updated_at,
           MAX(CASE status WHEN 'Completed' THEN 3 WHEN 'In progress' THEN 2 ELSE 1 END) AS best_rank,
           (ARRAY_AGG(status ORDER BY updated_at DESC, id DESC))[1] AS latest_status,
           (ARRAY_AGG(scorm_state ORDER BY updated_at DESC, id DESC)
              FILTER (WHERE scorm_state IS NOT NULL AND scorm_state <> '{}'::jsonb))[1] AS scorm_state
    FROM learning_module_tracks
    WHERE user_id IS NOT NULL AND learning_module_id IS NOT NULL
    GROUP BY user_id, learning_module_id
    HAVING COUNT(*) > 1
  SQL

  def up
    report_groups

    transaction do
      execute(<<~SQL.squish)
        UPDATE learning_module_tracks t
        SET created_at = g.first_created_at,
            updated_at = g.last_updated_at,
            scorm_state = COALESCE(g.scorm_state, t.scorm_state),
            status = CASE
                       WHEN g.best_rank = 3 OR g.scorm_state ->> 'cmi.completion_status' = 'completed' THEN 'Completed'
                       WHEN g.best_rank = 2 THEN 'In progress'
                       ELSE g.latest_status
                     END
        FROM (#{GROUPS}) g
        WHERE t.id = g.keeper_id
      SQL

      result = execute(<<~SQL.squish)
        DELETE FROM learning_module_tracks t
        USING (
          SELECT user_id, learning_module_id,
                 (ARRAY_AGG(id ORDER BY created_at, id))[1] AS keeper_id
          FROM learning_module_tracks
          WHERE user_id IS NOT NULL AND learning_module_id IS NOT NULL
          GROUP BY user_id, learning_module_id
          HAVING COUNT(*) > 1
        ) g
        WHERE t.user_id = g.user_id AND t.learning_module_id = g.learning_module_id AND t.id <> g.keeper_id
      SQL
      say "learning_module_tracks: #{result.cmd_tuples} duplicate rows merged away"
    end
  end

  # The merged rows cannot be split apart again.
  def down; end

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
