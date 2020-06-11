# frozen_string_literal: true

class AddLeveltoProficientProjects < ActiveRecord::Migration[5.0]
  def change
    add_column :proficient_projects, :level, :string, default: 'Beginner'
  end
end
