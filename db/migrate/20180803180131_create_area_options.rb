# frozen_string_literal: true

class CreateAreaOptions < ActiveRecord::Migration[5.0]
  def change
    create_table :area_options do |t|
      t.string :name

      t.timestamps null: false
    end
  end
end
