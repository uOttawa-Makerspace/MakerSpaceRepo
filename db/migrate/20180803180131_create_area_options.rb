# frozen_string_literal: true

class CreateAreaOptions < ActiveRecord::Migration
  def change
    create_table :area_options do |t|
      t.string :name

      t.timestamps null: false
    end
  end
end
