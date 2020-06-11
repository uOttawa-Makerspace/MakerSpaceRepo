class CreateBadges < ActiveRecord::Migration
  def change
    create_table :badges do |t|
      t.string :user
      t.string :image_url
      t.string :issued_to
      t.string :description

      t.timestamps null: false
    end
  end
end
