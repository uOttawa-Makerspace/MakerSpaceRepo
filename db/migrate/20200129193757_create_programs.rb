# frozen_string_literal: true

class CreatePrograms < ActiveRecord::Migration[5.0]
  def change
    create_table :programs do |t|
      t.integer :user_id
      t.string :program_type

      t.timestamps null: false
    end
  end
end
