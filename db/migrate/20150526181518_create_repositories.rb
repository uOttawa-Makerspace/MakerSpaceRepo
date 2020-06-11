# frozen_string_literal: true

class CreateRepositories < ActiveRecord::Migration
  def change
    create_table :repositories do |t|
      t.references :user, index: true, foreign_key: true
      t.string :title
      t.string :description

      t.timestamps null: false
    end
  end
end
