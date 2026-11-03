require Rails.root.join("db/migrate/20261104000004_add_foreign_keys_to_unenforced_references")

# Validates the foreign keys that the previous migration added NOT VALID, and only
# those. Validation scans the child table under SHARE UPDATE EXCLUSIVE, which does not
# block reads or writes. Each validation commits on its own (no DDL transaction around the
# migration), so a failure part-way keeps the keys already validated and the migration can
# be run again: keys that are validated are skipped.
#
# A key whose table still holds a row pointing at a missing parent is reported
# with its count before anything is validated, so the rows can be repaired and
# the migration run again.
#
# repositories_users.repository_id stays unvalidated: the table holds a membership
# row of a repository that no longer exists. The key already refuses new such rows;
# the existing row is kept and the key is validated once that row is dealt with.
# training_sessions.space_id stays unvalidated for the same reason: a few sessions name a
# space id that never existed and are waiting to be pointed at the right space.
class ValidateForeignKeysOnUnenforcedReferences < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  UNVALIDATED = [[:repositories_users, :repository_id], [:training_sessions, :space_id]].freeze

  def up
    pending = pending_foreign_keys
    dangling = pending.filter_map do |fk|
      count = connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*) FROM #{quote_table_name(fk.from_table)} c
        WHERE c.#{quote_column_name(fk.column)} IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM #{quote_table_name(fk.to_table)} p
                          WHERE p.#{quote_column_name(fk.primary_key)} = c.#{quote_column_name(fk.column)})
      SQL
      "#{fk.from_table}.#{fk.column} (#{count})" if count.positive?
    end
    raise "References to missing rows remain, repair them first: #{dangling.join(', ')}" if dangling.any?

    pending.each { |fk| validate_foreign_key fk.from_table, column: fk.column }
  end

  # A validated key cannot be made unvalidated again; the keys themselves are
  # removed by the previous migration's down.
  def down; end

  private

  def pending_foreign_keys
    AddForeignKeysToUnenforcedReferences::REFERENCES.filter_map do |table, parent, column, _on_delete|
      next if UNVALIDATED.include?([table, column])

      foreign_keys(table).find { |fk| fk.column == column.to_s && fk.to_table == parent.to_s && !fk.validated? }
    end
  end
end
