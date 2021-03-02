class AddSpaceToUser < ActiveRecord::Migration[6.0]
  def change
    add_reference :users, :space, index: true, foreign_key: true
  end
end
