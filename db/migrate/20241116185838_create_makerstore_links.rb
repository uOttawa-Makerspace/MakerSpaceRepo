class CreateMakerstoreLinks < ActiveRecord::Migration[7.0]
  def change
    create_table :makerstore_links do |t|
      t.integer :order, default: 0
      t.string :title
      t.string :url
      t.string :image_url
      t.boolean :shown, default: true
    end
  end
end
