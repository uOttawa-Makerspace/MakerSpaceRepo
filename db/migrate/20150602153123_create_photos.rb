class CreatePhotos < ActiveRecord::Migration
  def change
    create_table :photos do |t|
      t.references :repository, index: true, foreign_key: true

      t.timestamps null: false
    end
  end
end
