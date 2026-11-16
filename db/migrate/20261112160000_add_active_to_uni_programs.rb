require Rails.root.join("lib/unique_index_guard")

# The programs import used to delete every row and insert the file again. It now keeps rows and marks the ones the
# file no longer lists as inactive, so the new `active` column is added (every existing row stays active) together with
# a unique index that lets a program be listed once per level and faculty while it is active.
#
# The shipped programs file lists one program twice with identical values, and the table stores it twice. The second
# copy is marked inactive (the row itself is kept untouched) so the index can be built. Any other duplicate stops the
# migration with a message; no row is ever removed or changed besides that flag. `down` drops the index and the column
# and leaves every row as it was.
class AddActiveToUniPrograms < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_uni_programs_on_program_level_faculty_active"

  def up
    add_column :uni_programs, :active, :boolean, default: true, null: false, if_not_exists: true
    retire_identical_copies
    add_unique_index_concurrently :uni_programs, %i[program level faculty], name: INDEX_NAME, where: "active"
  end

  def down
    remove_unique_index_concurrently :uni_programs, name: INDEX_NAME
    remove_column :uni_programs, :active, if_exists: true
  end

  private

  # Of rows identical in every column, the first stays active and the others become inactive.
  def retire_identical_copies
    execute <<~SQL.squish
      UPDATE uni_programs SET active = FALSE
      WHERE ctid IN (
        SELECT ctid FROM (
          SELECT ctid, row_number() OVER (PARTITION BY program, level, faculty, department ORDER BY ctid) AS copy
          FROM uni_programs WHERE active
        ) numbered WHERE copy > 1
      )
    SQL
  end
end
