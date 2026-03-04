class DropMakerstoreLinks < ActiveRecord::Migration[7.0]
  def up
    drop_table :makerstore_links
  end

  def down
    create_table :makerstore_links do |t|
      t.string :title
      t.string :url
      t.string :image
      t.integer :order
      t.boolean :shown
      t.timestamps
    end
  end
end