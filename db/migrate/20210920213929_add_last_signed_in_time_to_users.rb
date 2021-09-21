class AddLastSignedInTimeToUsers < ActiveRecord::Migration[6.0]
  def self.up
    add_column :users, :last_signed_in_time, :timestamp
    User.update_all(last_signed_in_time: DateTime.now)
  end

  def self.down
    remove_column :users, :last_signed_in_time
  end
end
