# frozen_string_literal: true

class CreateExams < ActiveRecord::Migration[5.0]
  def change
    create_table :exams do |t|
      t.integer :user_id
      t.string :category

      t.timestamps null: false
    end
  end
end
