# frozen_string_literal: true

class CreateSkills < ActiveRecord::Migration
  def change
    create_table :skills do |t|
      t.integer :user_id
      t.string :printing
      t.string :laser_cutting
      t.string :virtual_reality
      t.string :arduino
      t.string :embroidery

      t.timestamps null: false
    end
  end
end
