class CreateProjectJoins < ActiveRecord::Migration
  def change
    create_table :project_joins do |t|
      t.integer :user_id
      t.integer :project_id

      t.timestamps null: false
    end
  end
end
