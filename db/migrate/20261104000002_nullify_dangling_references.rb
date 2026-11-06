# Optional references that point at a row which no longer exists are cleared, so
# the foreign keys added next can be created and validated. Only the reference
# is cleared: every row, with its other columns and history, stays. The dangling
# id points at nothing, so no information is lost.
#
# Four training sessions created in one batch name space 0, which never existed; the
# other two sessions of that batch are in space 16, so those four are pointed at space 16
# first (the owner confirmed it). The migration stops if space 16 does not exist.
#
# Every cleared value, and every moved session, is copied into nullified_references (table,
# row, column, old value, written value) by the statement that changes it, so down can put
# each one back. Safe to run again: the second run finds nothing to clear and archives nothing.
class NullifyDanglingReferences < ActiveRecord::Migration[8.1]
  ARCHIVE = "nullified_references"
  SOURCE = "20261104000002"

  REFERENCES = [
    [:exam_responses, :answer_id, :answers],
    [:exam_questions, :question_id, :questions],
    [:training_sessions_users, :user_id, :users],
    [:require_trainings, :volunteer_task_id, :volunteer_tasks],
    [:repositories, :make_id, :repositories],
    [:certifications, :training_session_id, :training_sessions]
  ].freeze
  TABLES_WITHOUT_ID = %w[training_sessions_users].freeze

  REMAPPED_SESSION_IDS = [1947, 1948, 1949, 1951].freeze
  REMAPPED_FROM_SPACE = 0
  REMAPPED_TO_SPACE = 16

  def up
    create_archive_table
    remap_sessions_to_space
    REFERENCES.each do |table, column, parent|
      result = change_and_archive(table, column, nil, <<~SQL.squish)
        t.#{column} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM #{parent} p WHERE p.id = t.#{column})
      SQL
      say "#{table}.#{column}: #{result.cmd_tuples} dangling references cleared"
    end
  end

  # Puts every archived value back where the column still holds what this migration wrote
  # (a value staff changed since is left alone). Raises, changing nothing, unless every
  # archived value is put back; the archive is dropped only after that.
  def down
    unless table_exists?(ARCHIVE)
      raise "#{ARCHIVE} is missing: this database ran a version of the migration that did not record its changes, " \
            "so they cannot be restored; nothing was changed"
    end

    archived = select_value("SELECT COUNT(*) FROM #{ARCHIVE} WHERE migration_version = '#{SOURCE}'").to_i
    restored = select_rows("SELECT DISTINCT table_name, column_name FROM #{ARCHIVE} WHERE migration_version = '#{SOURCE}'").sum do |table, column|
      restore_column(table, column)
    end
    if restored != archived
      raise "Cannot restore #{ARCHIVE}: put back #{restored} of #{archived} values (the others were changed since or their rows are gone); " \
            "nothing was changed and the archive was kept"
    end

    execute "DROP TABLE #{ARCHIVE}"
  end

  private

  def create_archive_table
    create_table ARCHIVE, if_not_exists: true do |t|
      t.text :migration_version, null: false
      t.text :table_name, null: false
      t.bigint :row_id
      t.text :column_name, null: false
      t.bigint :old_value
      t.bigint :new_value
      t.jsonb :row_data, null: false
      t.datetime :archived_at, null: false, default: -> { "now()" }
    end
  end

  # Archives the rows matching the condition, then sets the column to new_value (NULL when
  # nil) in the same statement. The rows are found once, so the archive and the change agree.
  def change_and_archive(table, column, new_value, condition)
    id_column = TABLES_WITHOUT_ID.include?(table.to_s) ? nil : "id"
    new_sql = new_value.nil? ? "NULL" : new_value.to_i
    execute(<<~SQL.squish)
      WITH targets AS (
        SELECT t.ctid AS tid, #{id_column ? "t.#{id_column}" : 'NULL::bigint'} AS row_id,
               t.#{column} AS old_value, to_jsonb(t) AS row_data
        FROM #{table} t WHERE #{condition} FOR UPDATE
      ), archived AS (
        INSERT INTO #{ARCHIVE} (migration_version, table_name, row_id, column_name, old_value, new_value, row_data)
        SELECT '#{SOURCE}', '#{table}', row_id, '#{column}', old_value, #{new_sql}, row_data FROM targets
        RETURNING 1
      )
      UPDATE #{table} SET #{column} = #{new_sql} FROM targets WHERE #{table}.ctid = targets.tid
    SQL
  end

  # Rows with an id are matched by it; a table without one by the whole old row with the
  # column written back as it was left (identical rows are interchangeable).
  def restore_column(table, column)
    if TABLES_WITHOUT_ID.exclude?(table)
      execute(<<~SQL.squish).cmd_tuples
        UPDATE #{table} t SET #{column} = a.old_value FROM #{ARCHIVE} a
        WHERE a.migration_version = '#{SOURCE}' AND a.table_name = '#{table}' AND a.column_name = '#{column}'
          AND t.id = a.row_id AND t.#{column} IS NOT DISTINCT FROM a.new_value
      SQL
    else
      select_rows("SELECT old_value, row_data::text FROM #{ARCHIVE} WHERE migration_version = '#{SOURCE}' AND table_name = '#{table}' AND column_name = '#{column}'").count do |old_value, row|
        restore_unnumbered_row(table, column, old_value, row)
      end
    end
  end

  def restore_unnumbered_row(table, column, old_value, row)
    written_row = "jsonb_set(#{quote(row)}::jsonb, '{#{column}}', 'null'::jsonb)"
    execute(<<~SQL.squish).cmd_tuples.positive?
      UPDATE #{table} SET #{column} = #{old_value.to_i}
      WHERE ctid = (SELECT ctid FROM #{table} t WHERE to_jsonb(t) = #{written_row} LIMIT 1 FOR UPDATE)
    SQL
  end

  def remap_sessions_to_space
    ids = REMAPPED_SESSION_IDS.join(', ')
    pending = select_value("SELECT COUNT(*) FROM training_sessions WHERE id IN (#{ids}) AND space_id = #{REMAPPED_FROM_SPACE}").to_i
    return if pending.zero?

    unless select_value("SELECT 1 FROM spaces WHERE id = #{REMAPPED_TO_SPACE}")
      raise "Cannot point training sessions #{ids} at space #{REMAPPED_TO_SPACE}: that space does not exist"
    end

    result = change_and_archive(:training_sessions, :space_id, REMAPPED_TO_SPACE,
                                "t.id IN (#{ids}) AND t.space_id = #{REMAPPED_FROM_SPACE}")
    say "training_sessions.space_id: #{result.cmd_tuples} sessions moved from space #{REMAPPED_FROM_SPACE} to space #{REMAPPED_TO_SPACE}"
  end
end
