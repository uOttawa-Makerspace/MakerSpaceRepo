# Builds a plain btree index on columns (optionally unique) CONCURRENTLY and
# is safe to re-run. A concurrent build that fails or is cancelled leaves an
# INVALID index, which `if_not_exists: true` would skip forever.
#
#   add_index_concurrently(table, columns, name:, unique: false)
#
# - no index of that name on the table: built.
# - a VALID, plain index with the same columns in the same order and the same
#   uniqueness: kept as is. Plain means btree, no where, include, expression,
#   order, opclass or nulls_not_distinct.
# - a VALID index of that name that is anything else: raises
#   IndexDefinitionMismatch.
# - an INVALID index on the table: dropped concurrently, then rebuilt.
# - the name used by any other relation in the table's schema: raises
#   IndexDefinitionMismatch (`IF NOT EXISTS` matches names schema-wide and
#   would skip the build silently).
#
# For a migration that calls `disable_ddl_transaction!`, from `up`/`down` or a
# `reversible` block; calling it while reverting raises ArgumentError.
#
# Any INVALID index of that name counts as a leftover, so a manual CREATE INDEX
# CONCURRENTLY of the same name running at the same time would be dropped.
# Migrations are serialised by Rails' advisory lock, so two migrators cannot
# collide.
#
#   include ConcurrentIndexBuilder
#   add_index_concurrently :events, %i[space_id draft], name: "idx_..."
module ConcurrentIndexBuilder
  class IndexDefinitionMismatch < StandardError; end

  def add_index_concurrently(table, columns, name:, unique: false)
    raise ArgumentError, "add_index_concurrently cannot be reverted; write explicit up/down or use reversible" if reverting?

    columns = Array(columns).map(&:to_s)
    raise_if_name_taken_by_other_relation(table, name)

    existing = indexes(table).find { |i| i.name == name }
    if existing.nil?
      # build below
    elsif !existing.valid?
      remove_index table, name: name, algorithm: :concurrently
    elsif !plain_match?(existing, columns, unique)
      raise IndexDefinitionMismatch,
            "index #{name} on #{table} exists as #{describe(existing)}, " \
            "not the requested #{'unique ' if unique}plain btree (#{columns.join(', ')})"
    end
    add_index table, columns, name: name, unique: unique, algorithm: :concurrently, if_not_exists: true
  end

  private

  def plain_match?(index, columns, unique)
    index.columns == columns && index.unique == unique && plain?(index)
  end

  def plain?(index)
    index.columns.is_a?(Array) &&
      (index.using || :btree).to_s == "btree" &&
      index.where.nil? &&
      index.include.blank? &&
      index.orders.blank? &&
      index.opclasses.blank? &&
      !index.nulls_not_distinct
  end

  def describe(index)
    columns = Array(index.columns).join(", ")
    extras = []
    extras << "where #{index.where}" if index.where
    extras << "include (#{Array(index.include).join(', ')})" if index.include.present?
    extras << "order #{index.orders}" if index.orders.present?
    extras << "opclass #{index.opclasses}" if index.opclasses.present?
    extras << "nulls not distinct" if index.nulls_not_distinct
    extras << "expression" unless index.columns.is_a?(Array)
    "#{'unique ' if index.unique}#{index.using || :btree} (#{columns})#{" #{extras.join(' ')}" if extras.any?}"
  end

  # Any relation of that name in the table's schema, except an index on this table.
  def raise_if_name_taken_by_other_relation(table, name)
    row = connection.select_one(<<~SQL.squish)
      SELECT c.relkind, t.relname AS table_name
      FROM pg_class c
      LEFT JOIN pg_index i ON i.indexrelid = c.oid
      LEFT JOIN pg_class t ON t.oid = i.indrelid
      WHERE c.relname = #{connection.quote(name)}
        AND c.relnamespace = (SELECT relnamespace FROM pg_class WHERE oid = #{connection.quote(connection.quote_table_name(table))}::regclass)
    SQL
    return if row.nil? || (row["relkind"] == "i" && row["table_name"] == table.to_s)

    raise IndexDefinitionMismatch,
          "#{name} is already used by another relation (relkind #{row['relkind']}#{", on table #{row['table_name']}" if row['table_name']}), not an index on #{table}"
  end
end
