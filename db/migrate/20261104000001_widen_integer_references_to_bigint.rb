# Columns that reference a bigint id were 32-bit integers. Widened first so the
# foreign keys added next join columns of the same width. Every other integer
# *_id column references an integer (serial) id and stays as it is.
#
# Each change rewrites its table under an ACCESS EXCLUSIVE lock; the three tables
# are small (a few thousand rows), so the locks are held for milliseconds.
class WidenIntegerReferencesToBigint < ActiveRecord::Migration[8.1]
  COLUMNS = [
    [:photos, :learning_module_id],
    [:repo_files, :learning_module_id],
    [:training_sessions, :course_name_id]
  ].freeze

  def up
    COLUMNS.each { |table, column| change_column table, column, :bigint }
  end

  def down
    COLUMNS.each { |table, column| change_column table, column, :integer }
  end
end
