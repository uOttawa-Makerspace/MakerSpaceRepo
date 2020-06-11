# frozen_string_literal: true

class CreateQuestions < ActiveRecord::Migration
  def change
    create_table :questions do |t|
      t.integer :user_id
      t.text :description
      t.string :category

      t.timestamps null: false
    end
  end
end
