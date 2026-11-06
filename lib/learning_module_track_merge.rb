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
# - scorm_state: when the group is completed, that of the most recently updated row that
#   is itself completed (status Completed, or a state reporting completion) and has a
#   non-empty state, so a finished attempt keeps its score and bookmark even if a newer
#   row holds a partial state; otherwise that of the most recently updated row with a
#   non-empty state (bookmark, suspend data and score travel together with it).
# - A row whose own state reports completion makes the merged status Completed.
# The other rows of the group are then removed: everything they held is on the kept row.
module LearningModuleTrackMerge
  ARCHIVE_TABLE = "learning_module_tracks_merged"

  # group: the columns that make rows "the same track" (default: user and module).
  # where: extra SQL condition, already sanitized, limiting the rows considered.
  # keeper_order: SQL ORDER BY expression picking the row that is kept.
  # source: names the caller in the archive (the migration version or the rake task).
  # Every removed row is copied in full into learning_module_tracks_merged, with the kept
  # row's id and the kept row's values before and after the merge, by the same statement
  # that changes the data. Returns the number of rows removed.
  def self.merge!(connection, source:, group: %w[user_id learning_module_id], where: "TRUE", keeper_order: "created_at, id")
    group_by = group.map { |column| connection.quote_column_name(column) }.join(", ")
    result = connection.execute(<<~SQL.squish)
      WITH g AS (
        SELECT (ARRAY_AGG(id ORDER BY #{keeper_order}))[1] AS keeper_id,
               ARRAY_AGG(id) AS ids,
               MIN(created_at) AS first_created_at,
               MAX(updated_at) AS last_updated_at,
               MAX(CASE status WHEN 'Completed' THEN 3 WHEN 'In progress' THEN 2 ELSE 1 END) AS best_rank,
               (ARRAY_AGG(status ORDER BY updated_at DESC, id DESC))[1] AS latest_status,
               COALESCE(BOOL_OR(scorm_state ->> 'cmi.completion_status' = 'completed'), FALSE) AS state_completed,
               (ARRAY_AGG(scorm_state ORDER BY updated_at DESC, id DESC)
                  FILTER (WHERE scorm_state IS NOT NULL AND scorm_state <> '{}'::jsonb
                            AND (status = 'Completed' OR scorm_state ->> 'cmi.completion_status' = 'completed')))[1] AS completed_scorm_state,
               (ARRAY_AGG(scorm_state ORDER BY updated_at DESC, id DESC)
                  FILTER (WHERE scorm_state IS NOT NULL AND scorm_state <> '{}'::jsonb))[1] AS newest_scorm_state
        FROM learning_module_tracks
        WHERE user_id IS NOT NULL AND learning_module_id IS NOT NULL AND (#{where})
        GROUP BY #{group_by}
        HAVING COUNT(*) > 1
      ), m AS (
        SELECT g.keeper_id, g.ids,
               g.first_created_at AS created_at,
               g.last_updated_at AS updated_at,
               COALESCE(g.completed_scorm_state, g.newest_scorm_state, k.scorm_state) AS scorm_state,
               CASE
                 WHEN g.best_rank = 3 OR g.state_completed THEN 'Completed'
                 WHEN g.best_rank = 2 THEN 'In progress'
                 ELSE g.latest_status
               END AS status,
               #{keeper_values('k')} AS keeper_before
        FROM g JOIN learning_module_tracks k ON k.id = g.keeper_id
      ), kept AS (
        UPDATE learning_module_tracks t
        SET created_at = m.created_at, updated_at = m.updated_at, scorm_state = m.scorm_state, status = m.status
        FROM m
        WHERE t.id = m.keeper_id
        RETURNING t.id
      ), archived AS (
        INSERT INTO #{ARCHIVE_TABLE} (merged_id, keeper_id, source, row_data, keeper_before, keeper_after, archived_at)
        SELECT t.id, m.keeper_id, #{connection.quote(source)}, to_jsonb(t), m.keeper_before, #{keeper_values('m')}, now()
        FROM m JOIN learning_module_tracks t ON t.id = ANY(m.ids) AND t.id <> m.keeper_id
        RETURNING merged_id
      )
      DELETE FROM learning_module_tracks t
      USING m
      WHERE t.id = ANY(m.ids) AND t.id <> m.keeper_id
    SQL
    result.cmd_tuples
  end

  # Puts back what merge! removed for one source: the removed rows with their ids, and each
  # kept row's values before the merge, only where the kept row still holds what the merge
  # gave it (a track the learner went on with since is left as it is). Raises, changing
  # nothing, if a removed row cannot be put back. Returns
  # { restored:, keepers_restored:, keepers_left: }; the archived rows of that source are
  # deleted once every one is back, and the table is dropped when nothing else is in it.
  def self.restore!(connection, source:)
    connection.transaction(requires_new: true) { restore_in_transaction(connection, source) }
  end

  def self.restore_in_transaction(connection, source)
    quoted = connection.quote(source)
    archived = connection.select_value("SELECT COUNT(*) FROM #{ARCHIVE_TABLE} WHERE source = #{quoted}").to_i
    restored = connection.execute(<<~SQL.squish).cmd_tuples
      INSERT INTO learning_module_tracks
      SELECT (jsonb_populate_record(NULL::learning_module_tracks, row_data)).*
      FROM #{ARCHIVE_TABLE} WHERE source = #{quoted}
      ON CONFLICT (id) DO NOTHING
    SQL
    if restored != archived
      raise "learning_module_tracks: only #{restored} of #{archived} merged rows could be put back " \
            "(a row with the same id exists); nothing was changed and #{ARCHIVE_TABLE} was kept"
    end

    result = restore_keepers(connection, quoted).merge(restored: restored)
    connection.execute("DELETE FROM #{ARCHIVE_TABLE} WHERE source = #{quoted}")
    connection.drop_table(ARCHIVE_TABLE) if connection.select_value("SELECT COUNT(*) FROM #{ARCHIVE_TABLE}").to_i.zero?
    result
  end

  def self.keeper_values(alias_name)
    "jsonb_build_object('status', #{alias_name}.status, 'created_at', #{alias_name}.created_at, " \
      "'updated_at', #{alias_name}.updated_at, 'scorm_state', #{alias_name}.scorm_state)"
  end
  private_class_method :keeper_values, :restore_in_transaction

  # Newest archive row first, so a kept row merged twice goes back through both states.
  def self.restore_keepers(connection, quoted_source)
    rows = connection.select_rows(<<~SQL.squish)
      SELECT keeper_id, keeper_before::text, keeper_after::text FROM #{ARCHIVE_TABLE}
      WHERE source = #{quoted_source} AND keeper_before <> keeper_after ORDER BY id DESC
    SQL
    matched = rows.filter_map do |keeper_id, before, after|
      next unless connection.execute(<<~SQL.squish).cmd_tuples.positive?
        UPDATE learning_module_tracks t
        SET (status, created_at, updated_at, scorm_state) =
            (SELECT r.status, r.created_at, r.updated_at, r.scorm_state
             FROM jsonb_populate_record(NULL::learning_module_tracks, #{connection.quote(before)}::jsonb) r)
        WHERE t.id = #{keeper_id.to_i} AND #{keeper_values('t')} = #{connection.quote(after)}::jsonb
      SQL

      keeper_id
    end.uniq
    { keepers_restored: matched.size, keepers_left: rows.map(&:first).uniq.size - matched.size }
  end
  private_class_method :restore_keepers
end
