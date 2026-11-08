require Rails.root.join("lib/unique_index_guard")

# One like per user and repository. The model validated this, which two simultaneous requests could both
# pass. If duplicates exist the migration stops and lists them; it never removes rows.
class AddUniqueIndexToLikes < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_likes_on_user_id_and_repository_id"

  def up
    add_unique_index_concurrently :likes, %i[user_id repository_id], name: INDEX_NAME
  end

  def down
    remove_unique_index_concurrently :likes, name: INDEX_NAME
  end
end
