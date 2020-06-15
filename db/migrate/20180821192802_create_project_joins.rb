# frozen_string_literal: true

class CreateProjectJoins < ActiveRecord::Migration[5.0]
  def change
    create_table :project_joins do |t|
      t.integer :user_id
      t.integer :project_id

      t.timestamps null: false
    end
  end
end
