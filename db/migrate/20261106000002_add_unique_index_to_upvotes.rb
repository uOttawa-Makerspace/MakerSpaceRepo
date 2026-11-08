require Rails.root.join("lib/unique_index_guard")

# One vote per user and comment. The model validated this, which two simultaneous requests could both pass.
# If duplicates exist the migration stops and lists them; it never removes rows.
class AddUniqueIndexToUpvotes < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_upvotes_on_user_id_and_comment_id"

  def up
    add_unique_index_concurrently :upvotes, %i[user_id comment_id], name: INDEX_NAME
  end

  def down
    remove_unique_index_concurrently :upvotes, name: INDEX_NAME
  end
end
