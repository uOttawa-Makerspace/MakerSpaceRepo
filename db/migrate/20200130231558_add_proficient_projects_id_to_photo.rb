# frozen_string_literal: true

class AddProficientProjectsIdToPhoto < ActiveRecord::Migration[5.0]
  def change
    add_column :photos, :proficient_project_id, :integer
  end
end
