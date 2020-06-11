# frozen_string_literal: true

class CreateEquipmentOptions < ActiveRecord::Migration
  def change
    create_table :equipment_options do |t|
      t.string :name

      t.timestamps null: false
    end
  end
end
