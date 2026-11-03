require Rails.root.join("lib/concurrent_index_builder")

# A user has one track per learning module. The model's uniqueness validation
# cannot hold under concurrent requests; this index does. Built CONCURRENTLY so
# writes to the table are not blocked. The previous migration merged the existing
# duplicates. The plain user_id index is covered by this one (user_id leads) and
# is dropped.
class AddUniqueIndexToLearningModuleTracks < ActiveRecord::Migration[8.1]
  include ConcurrentIndexBuilder
  disable_ddl_transaction!

  def up
    add_index_concurrently :learning_module_tracks, %i[user_id learning_module_id],
                           name: "index_learning_module_tracks_on_user_and_learning_module", unique: true
    remove_index :learning_module_tracks, name: "index_learning_module_tracks_on_user_id",
                                          algorithm: :concurrently, if_exists: true
  end

  def down
    add_index_concurrently :learning_module_tracks, :user_id, name: "index_learning_module_tracks_on_user_id"
    remove_index :learning_module_tracks, name: "index_learning_module_tracks_on_user_and_learning_module",
                                          algorithm: :concurrently, if_exists: true
  end
end
