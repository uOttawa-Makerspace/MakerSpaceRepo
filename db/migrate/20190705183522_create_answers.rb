# frozen_string_literal: true

class CreateAnswers < ActiveRecord::Migration[5.0]
  def change
    create_table :answers do |t|
      t.integer :question_id
      t.text :description
      t.boolean :correct, default: false

      t.timestamps null: false
    end
  end
end
