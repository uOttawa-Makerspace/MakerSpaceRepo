# frozen_string_literal: true

class EditCertificationTraingIdToTrainingName < ActiveRecord::Migration[5.0]
  def change
    remove_column :certifications, :training_id, :string
    add_column :certifications, :training_name, :string
  end
end
