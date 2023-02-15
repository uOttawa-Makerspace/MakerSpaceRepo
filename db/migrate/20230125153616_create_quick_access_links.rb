class CreateQuickAccessLinks < ActiveRecord::Migration[6.1]
  def change
    create_table :quick_access_links do |t|
      t.string :name
      t.string :path
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
  end
end
