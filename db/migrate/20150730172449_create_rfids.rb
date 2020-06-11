# frozen_string_literal: true

class CreateRfids < ActiveRecord::Migration[5.0]
  def change
    create_table :rfids do |t|
      t.references :user, index: true, foreign_key: true
      t.string :card_number

      t.timestamps null: false
    end
  end
end
