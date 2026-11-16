# Two spaces may not share a name, ignoring case. Until now only the model checked it (and case-sensitively), so
# a concurrent or differently cased save could add a second space with the same name. If names already repeat,
# ignoring case, the migration stops and lists the rows; it never changes or removes rows. The spaces table is
# a handful of rows, so the index is built inside the migration's transaction.
class AddUniqueIndexToSpacesLowerName < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_spaces_on_lower_name".freeze

  class DuplicatesFound < StandardError; end

  def up
    refuse_duplicate_names
    add_index :spaces, "lower(name)", name: INDEX_NAME, unique: true, if_not_exists: true
  end

  def down
    remove_index :spaces, name: INDEX_NAME, if_exists: true
  end

  private

  def refuse_duplicate_names
    groups = select_rows(<<~SQL.squish)
      SELECT lower(name), array_to_string(array_agg(id ORDER BY id), ',')
      FROM spaces WHERE name IS NOT NULL
      GROUP BY lower(name) HAVING count(*) > 1 ORDER BY min(id)
    SQL
    return if groups.empty?

    raise DuplicatesFound,
          "spaces has #{groups.size} name(s) used more than once, ignoring case, so the unique index cannot be " \
          "built. Nothing was changed. Rename these by hand, then run the migration again:\n  " +
          groups.map { |name, ids| "#{name.inspect} -> ids #{ids}" }.join("\n  ")
  end
end
