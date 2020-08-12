class CreateProjectKits < ActiveRecord::Migration[6.0]
  def change
    create_table :project_kits do |t|
      t.references :user, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: :true
      t.string :name
      t.boolean :delivered, default: false

      t.timestamps
    end
  end
end
