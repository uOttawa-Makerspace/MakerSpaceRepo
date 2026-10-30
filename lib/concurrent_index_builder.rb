# Build an index CONCURRENTLY (no write lock) and survive an interrupted
# earlier attempt. A concurrent build that fails or is cancelled leaves an
# INVALID index under the same name, which `if_not_exists: true` would then
# skip forever. This drops such a leftover first, so the build always ends
# with a valid index and is safe to re-run.
#
# Include in a migration that calls `disable_ddl_transaction!`:
#
#   require Rails.root.join("lib/concurrent_index_builder")
#   include ConcurrentIndexBuilder
#   add_index_concurrently :events, %i[space_id draft], name: "idx_..."
module ConcurrentIndexBuilder
  def add_index_concurrently(table, columns, name: nil, **options)
    name ||= index_name(table, column: columns)
    remove_index table, name: name, algorithm: :concurrently if invalid_index?(name)
    add_index table, columns, name: name, algorithm: :concurrently, if_not_exists: true, **options
  end

  private

  def invalid_index?(name)
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = #{connection.quote(name)}
        AND c.relnamespace = current_schema()::regnamespace
        AND NOT i.indisvalid
    SQL
  end
end
