# Optional references that point at a row which no longer exists are cleared, so
# the foreign keys added next can be created and validated. Only the reference
# is cleared: every row, with its other columns and history, stays. The dangling
# id points at nothing, so no information is lost.
#
# Safe to run again: the second run finds nothing to clear.
class NullifyDanglingReferences < ActiveRecord::Migration[8.1]
  REFERENCES = [
    [:exam_responses, :answer_id, :answers],
    [:exam_questions, :question_id, :questions],
    [:training_sessions_users, :user_id, :users],
    [:training_sessions, :space_id, :spaces],
    [:require_trainings, :volunteer_task_id, :volunteer_tasks],
    [:repositories, :make_id, :repositories],
    [:certifications, :training_session_id, :training_sessions]
  ].freeze

  def up
    REFERENCES.each do |table, column, parent|
      result = execute(<<~SQL.squish)
        UPDATE #{table} SET #{column} = NULL
        WHERE #{column} IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM #{parent} p WHERE p.id = #{table}.#{column})
      SQL
      say "#{table}.#{column}: #{result.cmd_tuples} dangling references cleared"
    end
  end

  # A cleared reference cannot be restored: it pointed at a row that does not exist.
  def down; end
end
