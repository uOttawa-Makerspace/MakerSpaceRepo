# Build an index CONCURRENTLY (no write lock) and survive an interrupted
# earlier attempt. A concurrent build that fails or is cancelled leaves an
# INVALID index under the same name, which `if_not_exists: true` would then
# skip forever. This drops such a leftover first, so the build always ends
# with a valid index and is safe to re-run. A VALID index of that name with a
# different definition (columns or uniqueness) is never accepted silently: the
# helper raises instead of skipping or rebuilding it.
#
# Include in a migration that calls `disable_ddl_transaction!`, and call it
# from `up`/`down` or inside `reversible`, never directly in `change`: it
# reads the database, which a reverted `change` cannot replay (it raises
# there).
#
#   require Rails.root.join("lib/concurrent_index_builder")
#   include ConcurrentIndexBuilder
#   add_index_concurrently :events, %i[space_id draft], name: "idx_..."
#
# Concurrent runs: any INVALID index of that name is treated as a leftover, so
# a manual CREATE INDEX CONCURRENTLY of the same name running at the same time
# would be dropped under its feet. Two migrators cannot collide, because Rails
# serialises migrations with an advisory lock. (pg_stat_progress_create_index
# could detect a manual build, but a manual build of a migration-managed index
# is not a case worth extra untestable code.)
module ConcurrentIndexBuilder
  class IndexDefinitionMismatch < StandardError; end

  def add_index_concurrently(table, columns, name: nil, unique: false)
    raise ArgumentError, "add_index_concurrently cannot be used in a reverted `change`; call it from up/down or reversible" if reverting?

    name ||= index_name(table, column: columns)
    remove_index table, name: name, algorithm: :concurrently if invalid_index?(table, name)
    existing = indexes(table).find { |i| i.name == name }
    if existing
      wanted = [Array(columns).map(&:to_s), unique ? true : false]
      found = [existing.columns, existing.unique ? true : false]
      raise IndexDefinitionMismatch, "index #{name} on #{table} exists as (#{found[0].join(', ')})#{' unique' if found[1]}, not the requested (#{wanted[0].join(', ')})#{' unique' if wanted[1]}" if wanted != found
    end
    add_index table, columns, name: name, unique: unique, algorithm: :concurrently, if_not_exists: true
  end

  private

  def invalid_index?(table, name)
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = #{connection.quote(name)}
        AND i.indrelid = #{connection.quote(table.to_s)}::regclass
        AND NOT i.indisvalid
    SQL
  end
end
