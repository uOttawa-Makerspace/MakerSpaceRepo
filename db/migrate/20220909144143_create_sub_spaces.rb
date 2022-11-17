class CreateSubSpaces < ActiveRecord::Migration[6.1]
  def change
    create_table :sub_spaces do |t|
      t.string :name
      t.belongs_to :space, foreign_key: true
      t.timestamps
    end
    Space.all.each do |space|
      SubSpace.create(name: space.name, space_id: space.id)
    end
  end
end
