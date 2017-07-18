class ShareType < ActiveRecord::Migration
  def change
    add_column :repositories, :share_type, :string
  end
end
