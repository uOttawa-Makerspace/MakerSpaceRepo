# frozen_string_literal: true

class CreateSpaces < ActiveRecord::Migration[5.0]
  def change
    create_table :spaces do |t|
      t.string :name
      t.timestamps null: false
    end
  end
end
