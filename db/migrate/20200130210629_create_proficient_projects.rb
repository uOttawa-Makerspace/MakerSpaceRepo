# frozen_string_literal: true

class CreateProficientProjects < ActiveRecord::Migration
  def change
    create_table :proficient_projects do |t|
      t.integer :training_id
      t.string :title
      t.text :description

      t.timestamps null: false
    end
  end
end
