class Identity < ActiveRecord::Migration
  def change
  	add_column :users, :identity, :string
  end
end
