# frozen_string_literal: true

class EditCertificationNameToTraining < ActiveRecord::Migration[5.0]
  def change
    remove_column :certifications, :name, :string
    add_column :certifications, :training_id, :string
  end
end
