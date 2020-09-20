class CreateSkills < ActiveRecord::Migration[6.0]
  def change
    create_table :skills do |t|
      t.text :name
      t.timestamps
    end
  end
end
