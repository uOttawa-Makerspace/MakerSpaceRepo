require Rails.root.join("lib/unique_index_guard")

# A user holds a program (Development, Volunteer, Teams) at most once. Until now only a model validation
# enforced it, which two concurrent requests can both pass. If a user already holds a program twice the migration
# stops and lists the rows; it never changes or removes rows.
class AddUniqueIndexToProgramsUserAndType < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_programs_on_user_id_and_program_type"

  def up
    add_unique_index_concurrently :programs, %i[user_id program_type], name: INDEX_NAME
  end

  def down
    remove_unique_index_concurrently :programs, name: INDEX_NAME
  end
end
