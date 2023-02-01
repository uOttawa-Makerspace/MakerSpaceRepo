class CreateTrainingLevels < ActiveRecord::Migration[6.1]
  def up
    create_table :training_levels do |t|
      t.string :name
      t.references :space, null: false, foreign_key: true
      t.timestamps
    end

    Space.all.each do |space|
      TrainingLevel.create(name: "None", space: space)
      TrainingLevel.create(name: "Basic", space: space)
    end
  end
  def down
    TrainingLevel.destroy_all
    drop_table :training_levels
  end
end
