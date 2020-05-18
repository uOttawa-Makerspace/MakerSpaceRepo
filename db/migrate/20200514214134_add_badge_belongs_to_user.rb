class AddBadgeBelongsToUser < ActiveRecord::Migration
  def change
    change_table :badges do |t|
      t.belongs_to :user
    end
  end
end
