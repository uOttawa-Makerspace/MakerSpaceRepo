# frozen_string_literal: true

class AddSolderingToSkills < ActiveRecord::Migration
  def change
    add_column :skills, :soldering, :string, default: 'No Experience'
  end
end
