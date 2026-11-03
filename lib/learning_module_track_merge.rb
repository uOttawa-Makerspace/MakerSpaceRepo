# The one rule for combining several learning_module_tracks rows of the same user and
# learning module into one. Used by the migration that adds the unique index and by
# users:merge_duplicates, so the two cannot drift apart.
#
# The kept row takes
# - status: Completed if any row in the group is Completed (or the SCORM state kept says
#   so), else In progress if any is, else the most recently updated row's status; a
#   completion is never lost;
# - created_at: the earliest of the group;
# - updated_at: the latest of the group;
# - scorm_state: that of the most recently updated row that has a non-empty one
#   (bookmark, suspend data and score travel together with it).
# The other rows of the group are then removed: everything they held is on the kept row.
module LearningModuleTrackMerge
  # group: the columns that make rows "the same track" (default: user and module).
  # where: extra SQL condition, already sanitized, limiting the rows considered.
  # keeper_order: SQL ORDER BY expression picking the row that is kept.
  # Returns the number of rows removed.
  def self.merge!(connection, group: %w[user_id learning_module_id], where: "TRUE", keeper_order: "created_at, id")
    group_by = group.map { |column| connection.quote_column_name(column) }.join(", ")
    result = connection.execute(<<~SQL.squish)
      WITH g AS (
        SELECT (ARRAY_AGG(id ORDER BY #{keeper_order}))[1] AS keeper_id,
               ARRAY_AGG(id) AS ids,
               MIN(created_at) AS first_created_at,
               MAX(updated_at) AS last_updated_at,
               MAX(CASE status WHEN 'Completed' THEN 3 WHEN 'In progress' THEN 2 ELSE 1 END) AS best_rank,
               (ARRAY_AGG(status ORDER BY updated_at DESC, id DESC))[1] AS latest_status,
               (ARRAY_AGG(scorm_state ORDER BY updated_at DESC, id DESC)
                  FILTER (WHERE scorm_state IS NOT NULL AND scorm_state <> '{}'::jsonb))[1] AS scorm_state
        FROM learning_module_tracks
        WHERE user_id IS NOT NULL AND learning_module_id IS NOT NULL AND (#{where})
        GROUP BY #{group_by}
        HAVING COUNT(*) > 1
      ), kept AS (
        UPDATE learning_module_tracks t
        SET created_at = g.first_created_at,
            updated_at = g.last_updated_at,
            scorm_state = COALESCE(g.scorm_state, t.scorm_state),
            status = CASE
                       WHEN g.best_rank = 3 OR g.scorm_state ->> 'cmi.completion_status' = 'completed' THEN 'Completed'
                       WHEN g.best_rank = 2 THEN 'In progress'
                       ELSE g.latest_status
                     END
        FROM g
        WHERE t.id = g.keeper_id
        RETURNING t.id
      )
      DELETE FROM learning_module_tracks t
      USING g
      WHERE t.id = ANY(g.ids) AND t.id <> g.keeper_id
    SQL
    result.cmd_tuples
  end
end
