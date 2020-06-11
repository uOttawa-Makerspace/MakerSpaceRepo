# frozen_string_literal: true

class AddValuesToProficientProject < ActiveRecord::Migration[5.0]
  def change
    add_column :proficient_projects, :cc, :integer
    add_column :proficient_projects, :proficient, :boolean, default: true
  end
end
