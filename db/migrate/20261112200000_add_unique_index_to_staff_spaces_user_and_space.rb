require Rails.root.join("lib/unique_index_guard")

# A staff member is assigned to a space at most once. Until now nothing enforced it, so a repeated or concurrent
# assignment could add a second row (and a second calendar colour). If a pair already appears twice the migration
# stops and lists the rows; it never changes or removes rows.
class AddUniqueIndexToStaffSpacesUserAndSpace < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_staff_spaces_on_user_id_and_space_id"

  def up
    add_unique_index_concurrently :staff_spaces, %i[user_id space_id], name: INDEX_NAME
  end

  def down
    remove_unique_index_concurrently :staff_spaces, name: INDEX_NAME
  end
end
