# frozen_string_literal: true

class AddSolderingToSkills < ActiveRecord::Migration[5.0]
  def change
    add_column :skills, :soldering, :string, default: 'No Experience'
  end
end
