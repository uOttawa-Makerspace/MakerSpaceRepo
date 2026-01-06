class AddUniqueIndexToUserColumns < ActiveRecord::Migration[7.2]
  def change
    # Need to clean up existing duplicates
    Rake::Task['users:merge_duplicates'].invoke
    # Case-normalized index to speed up searches and prevent future duplicates
    add_index :users, 'LOWER(email)', unique: true, name: 'index_users_on_lowercase_email'
    add_index :users, 'LOWER(username)', unique: true, name: 'index_users_on_lowercase_username'
  end
end
