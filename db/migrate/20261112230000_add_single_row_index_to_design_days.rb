require Rails.root.join("lib/unique_index_guard")

# There is one Design Day record. The index is unique over a constant, so a second row is refused by the database
# (two simultaneous first visits to the settings page used to create two). If more than one row already exists the
# migration stops and lists their ids; it never changes or removes rows.
class AddSingleRowIndexToDesignDays < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_design_days_single_row"

  def up
    ids = select_values("SELECT id FROM design_days ORDER BY id")
    if ids.size > 1
      raise UniqueIndexGuard::DuplicatesFound,
            "design_days has #{ids.size} rows, so the single-row index cannot be built. Nothing was changed. " \
            "Decide which one to keep and resolve it by hand, then run the migration again: ids #{ids.join(',')}"
    end

    existing = indexes(:design_days).find { |i| i.name == INDEX_NAME }
    remove_index :design_days, name: INDEX_NAME, algorithm: :concurrently if existing && !existing.valid?
    add_index :design_days, "((true))", name: INDEX_NAME, unique: true, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :design_days, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
