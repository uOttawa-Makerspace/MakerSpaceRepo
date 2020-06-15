# frozen_string_literal: true

class AddTrainingIdToQuestions < ActiveRecord::Migration[5.0]
  def change
    add_column :questions, :training_id, :integer
  end
end
