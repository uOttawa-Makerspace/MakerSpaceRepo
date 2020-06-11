# frozen_string_literal: true

class CreateVideos < ActiveRecord::Migration[5.0]
  def change
    create_table :videos do |t|
      t.references :proficient_project, index: true, foreign_key: true

      t.timestamps null: false
    end
  end
end
