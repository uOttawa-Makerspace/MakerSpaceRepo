# frozen_string_literal: true

class CreateProjectRequirements < ActiveRecord::Migration
  def change
    create_table :project_requirements do |t|
      t.integer :proficient_project_id
      t.integer :required_project_id

      t.timestamps null: false
    end
  end
end
