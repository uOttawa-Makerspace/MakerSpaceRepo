# A space manager row always names a user and a space: space_manager_joins.user_id and space_id become NOT NULL.
# Rows missing either are counted first and the migration refuses to run while any exist; they are never repaired
# or removed automatically. The table is a handful of rows, so both columns change inside the migration's
# transaction, and a refusal changes nothing.
class RequireUserAndSpaceOnSpaceManagerJoins < ActiveRecord::Migration[8.1]
  COLUMNS = %i[user_id space_id].freeze

  def up
    refuse_rows_with_nulls
    COLUMNS.each { |column| change_column_null :space_manager_joins, column, false }
  end

  def down
    COLUMNS.each { |column| change_column_null :space_manager_joins, column, true }
  end

  private

  def refuse_rows_with_nulls
    counts = COLUMNS.index_with { |column| select_value("SELECT COUNT(*) FROM space_manager_joins WHERE #{column} IS NULL").to_i }
    missing = counts.reject { |_, count| count.zero? }.map { |column, count| "#{count} with no #{column}" }
    return if missing.empty?

    raise "space_manager_joins has rows without a value: #{missing.join(', ')}. " \
          "Nothing was changed. Decide what to do with those rows, then run the migration again."
  end
end
