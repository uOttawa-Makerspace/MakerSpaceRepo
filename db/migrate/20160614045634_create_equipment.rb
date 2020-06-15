# frozen_string_literal: true

class CreateEquipment < ActiveRecord::Migration[5.0]
  def change
    create_table :equipment do |t|
      t.references :repository, index: true, foreign_key: true
      t.string :name

      t.timestamps null: false
    end
  end
end
