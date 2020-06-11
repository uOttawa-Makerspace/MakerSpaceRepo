# frozen_string_literal: true

class AddActiveToSkill < ActiveRecord::Migration[5.0]
  def change
    add_column :skills, :active, :boolean, default: true
  end
end
