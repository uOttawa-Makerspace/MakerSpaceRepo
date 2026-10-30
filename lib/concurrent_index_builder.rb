# Build an index CONCURRENTLY (no write lock) and survive an interrupted
# earlier attempt. A concurrent build that fails or is cancelled leaves an
# INVALID index under the same name, which `if_not_exists: true` would then
# skip forever. This drops such a leftover first, so the build always ends
# with a valid index and is safe to re-run.
#
# The existing index is read with Rails' own `indexes(table)`
# (ActiveRecord::ConnectionAdapters::IndexDefinition):
#
# - INVALID (`valid?` false): dropped concurrently, then rebuilt.
# - VALID and `defined_for?` the request (columns or expression, unique,
#   include, nulls_not_distinct), `where` and `using` equal: kept untouched.
# - VALID but different: raises IndexDefinitionMismatch, never silently kept.
# - The name is used by an index on ANOTHER table of the schema: raises
#   (`CREATE INDEX IF NOT EXISTS` matches names schema-wide and would skip the
#   build without a word).
#
# Rails 8.1's `defined_for?` does not compare `where`, `using`, `order` or
# `opclass` (it swallows them), so the helper compares `where` and `using`
# itself; `order`/`opclass` are passed on to the build but not compared. A
# `where:` or expression is compared as PostgreSQL prints it back, ignoring
# whitespace and parentheses; a spelling PostgreSQL rewrites (e.g. a cast it
# adds to a string literal) is reported as a mismatch rather than accepted.
#
# Accepts the add_index options (unique:, where:, using:, include:, opclass:,
# order:, nulls_not_distinct:, comment:). `algorithm:` and `if_not_exists:` are
# owned by the helper and raise ArgumentError.
#
# Include in a migration that calls `disable_ddl_transaction!`. It works
# directly in `change`: reverted, it removes the index concurrently
# (`if_exists`), so a `reversible` wrapper is not needed. It can also be
# called from up/down.
#
#   require Rails.root.join("lib/concurrent_index_builder")
#   include ConcurrentIndexBuilder
#   add_index_concurrently :events, %i[space_id draft], name: "idx_..."
#
# Concurrent runs: any INVALID index of that name is treated as a leftover, so
# a manual CREATE INDEX CONCURRENTLY of the same name running at the same time
# would be dropped under its feet. Two migrators cannot collide, because Rails
# serialises migrations with an advisory lock.
module ConcurrentIndexBuilder
  class IndexDefinitionMismatch < StandardError; end

  OWNED_OPTIONS = %i[algorithm if_not_exists].freeze

  def add_index_concurrently(table, columns, name: nil, **options)
    owned = options.keys & OWNED_OPTIONS
    raise ArgumentError, "add_index_concurrently sets #{owned.join(', ')} itself" if owned.any?

    name ||= index_name(table, column: columns)

    if reverting?
      # inside a reverted `change`, `revert` turns the removal back into a plain one
      revert { remove_index table, name: name, algorithm: :concurrently, if_exists: true }
      return
    end

    options[:unique] = options.fetch(:unique, false)
    existing = indexes(table).find { |i| i.name == name }
    if existing.nil?
      raise_if_name_taken_elsewhere(table, name)
    elsif !existing.valid?
      remove_index table, name: name, algorithm: :concurrently
    elsif !matches?(existing, columns, options)
      raise IndexDefinitionMismatch,
            "index #{name} on #{table} exists as #{describe(existing.columns, existing.unique, existing.where, existing.using)}, " \
            "not the requested #{describe(columns, options[:unique], options[:where], options[:using])}"
    end
    add_index table, columns, name: name, algorithm: :concurrently, if_not_exists: true, **options
  end

  private

  def matches?(existing, columns, options)
    existing.defined_for?(columns, **options.slice(:unique, :include, :nulls_not_distinct)) &&
      same_sql?(existing.where, options[:where]) &&
      (existing.using || :btree).to_s == (options[:using] || :btree).to_s
  end

  def same_sql?(found, wanted)
    found.to_s.delete("() \n\t") == wanted.to_s.delete("() \n\t")
  end

  def describe(columns, unique, where, using)
    text = "#{'unique ' if unique}#{using || :btree} (#{Array(columns).join(', ')})"
    where.present? ? "#{text} where #{where}" : text
  end

  def raise_if_name_taken_elsewhere(table, name)
    other = select_value(<<~SQL.squish)
      SELECT tablename FROM pg_indexes
      WHERE schemaname = current_schema() AND indexname = #{connection.quote(name)}
    SQL
    return if other.nil?

    raise IndexDefinitionMismatch, "index name #{name} is already used on table #{other}, not #{table}"
  end
end
