# frozen_string_literal: true

class CreateExamResponses < ActiveRecord::Migration
  def change
    create_table :exam_responses do |t|
      t.integer :exam_question_id
      t.integer :answer_id
      t.boolean :correct

      t.timestamps null: false
    end
  end
end
