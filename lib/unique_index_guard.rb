# Adds a unique index (optionally partial) to a table that may already hold duplicates, without ever touching
# the rows: the migration stops with a message listing the offending ids, and the owner decides what to do
# with them.
#
#   include UniqueIndexGuard
#   disable_ddl_transaction!
#   add_unique_index_concurrently :likes, %i[user_id repository_id], name: "idx_..."
#   add_unique_index_concurrently :locker_rentals, :locker_id, name: "idx_...", where: "state IN ('active')"
#
# - Rows with a NULL in any index column never count as duplicates (as in the index itself).
# - The index is built CONCURRENTLY. An INVALID leftover of that name (a cancelled earlier build) is dropped and
#   rebuilt; a VALID one is kept.
module UniqueIndexGuard
  class DuplicatesFound < StandardError; end

  def add_unique_index_concurrently(table, columns, name:, where: nil)
    columns = Array(columns)
    raise_on_duplicates(table, columns, where)

    existing = indexes(table).find { |i| i.name == name }
    remove_index table, name: name, algorithm: :concurrently if existing && !existing.valid?
    add_index table, columns, name: name, unique: true, where: where, algorithm: :concurrently, if_not_exists: true
  end

  def remove_unique_index_concurrently(table, name:)
    remove_index table, name: name, algorithm: :concurrently, if_exists: true
  end

  private

  def raise_on_duplicates(table, columns, where)
    groups = duplicate_groups(table, columns, where)
    return if groups.empty?

    listing = groups.map { |ids, key| "#{columns.zip(key).map { |c, v| "#{c}=#{v}" }.join(', ')} -> ids #{ids}" }
    raise DuplicatesFound,
          "#{table} has #{groups.size} group(s) of duplicate rows, so the unique index cannot be built. " \
          "Nothing was changed. Resolve these by hand, then run the migration again:\n  #{listing.join("\n  ")}"
  end

  # [[ids, key values], ...] for every key held by more than one row.
  def duplicate_groups(table, columns, where)
    quoted = columns.map { |c| quote_column_name(c) }
    conditions = quoted.map { |c| "#{c} IS NOT NULL" }
    conditions << "(#{where})" if where
    rows = select_rows(<<~SQL.squish)
      SELECT array_to_string(array_agg(id ORDER BY id), ','), #{quoted.map { |c| "#{c}::text" }.join(', ')}
      FROM #{quote_table_name(table)}
      WHERE #{conditions.join(' AND ')}
      GROUP BY #{quoted.join(', ')}
      HAVING count(*) > 1
      ORDER BY min(id)
    SQL
    rows.map { |row| [row.first, row.drop(1)] }
  end
end
