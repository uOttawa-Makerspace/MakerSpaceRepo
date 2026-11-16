require Rails.root.join("lib/unique_index_guard")

# An owner holds a repository title at most once, hidden repositories included (the exact, case-sensitive rule the
# model validation applies). Until now only the validation enforced it, which two concurrent creates can both
# pass. If an owner already holds a title twice the migration stops and lists the rows; it never changes or
# removes rows.
class AddUniqueIndexToRepositoriesUserAndTitle < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_repositories_on_user_id_and_title"

  def up
    add_unique_index_concurrently :repositories, %i[user_id title], name: INDEX_NAME
  end

  def down
    remove_unique_index_concurrently :repositories, name: INDEX_NAME
  end
end
