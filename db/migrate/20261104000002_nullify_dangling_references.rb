# Optional references that point at a row which no longer exists are cleared, so
# the foreign keys added next can be created and validated. Only the reference
# is cleared: every row, with its other columns and history, stays. The dangling
# id points at nothing, so no information is lost.
#
# Four training sessions created in one batch name space 0, which never existed; the
# other two sessions of that batch are in space 16, so those four are pointed at space 16
# first (the owner confirmed it). The migration stops if space 16 does not exist.
#
# Safe to run again: the second run finds nothing to clear.
class NullifyDanglingReferences < ActiveRecord::Migration[8.1]
  REFERENCES = [
    [:exam_responses, :answer_id, :answers],
    [:exam_questions, :question_id, :questions],
    [:training_sessions_users, :user_id, :users],
    [:require_trainings, :volunteer_task_id, :volunteer_tasks],
    [:repositories, :make_id, :repositories],
    [:certifications, :training_session_id, :training_sessions]
  ].freeze

  REMAPPED_SESSION_IDS = [1947, 1948, 1949, 1951].freeze
  REMAPPED_FROM_SPACE = 0
  REMAPPED_TO_SPACE = 16

  def up
    remap_sessions_to_space
    REFERENCES.each do |table, column, parent|
      result = execute(<<~SQL.squish)
        UPDATE #{table} SET #{column} = NULL
        WHERE #{column} IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM #{parent} p WHERE p.id = #{table}.#{column})
      SQL
      say "#{table}.#{column}: #{result.cmd_tuples} dangling references cleared"
    end
  end

  # Nothing is undone. A cleared reference pointed at a row that does not exist, and the
  # remapped sessions stay in space 16: space 0 never existed, and a session staff later put
  # in space 16 must not be moved out of it.
  def down; end

  private

  def remap_sessions_to_space
    ids = REMAPPED_SESSION_IDS.join(', ')
    pending = select_value("SELECT COUNT(*) FROM training_sessions WHERE id IN (#{ids}) AND space_id = #{REMAPPED_FROM_SPACE}").to_i
    return if pending.zero?

    unless select_value("SELECT 1 FROM spaces WHERE id = #{REMAPPED_TO_SPACE}")
      raise "Cannot point training sessions #{ids} at space #{REMAPPED_TO_SPACE}: that space does not exist"
    end

    result = execute(<<~SQL.squish)
      UPDATE training_sessions SET space_id = #{REMAPPED_TO_SPACE}
      WHERE id IN (#{ids}) AND space_id = #{REMAPPED_FROM_SPACE}
    SQL
    say "training_sessions.space_id: #{result.cmd_tuples} sessions moved from space #{REMAPPED_FROM_SPACE} to space #{REMAPPED_TO_SPACE}"
  end
end
