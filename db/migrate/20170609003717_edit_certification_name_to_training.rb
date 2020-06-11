# frozen_string_literal: true

class EditCertificationNameToTraining < ActiveRecord::Migration
  def change
    remove_column :certifications, :name, :string
    add_column :certifications, :training_id, :string
  end
end
