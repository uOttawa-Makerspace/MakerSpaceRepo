class CreateVideos < ActiveRecord::Migration
  def change
    create_table :videos do |t|
      t.references :proficient_project, index: true, foreign_key: true

      t.timestamps null: false
    end
  end
end
