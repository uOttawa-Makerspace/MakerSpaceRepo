class DropBadgesTable < ActiveRecord::Migration[7.2]
  def up
    drop_table :badges
  end

  def down
    create_table :badges do |t|
      t.string :user
      t.string :image_url
      t.string :issued_to
      t.string :description

      t.timestamps null: false
    end
  end
end
