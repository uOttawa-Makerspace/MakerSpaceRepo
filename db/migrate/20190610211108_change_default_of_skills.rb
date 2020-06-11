# frozen_string_literal: true

class ChangeDefaultOfSkills < ActiveRecord::Migration[5.0]
  def up
    change_column :skills, :printing, :string, default: 'No Experience'
    change_column :skills, :laser_cutting, :string, default: 'No Experience'
    change_column :skills, :virtual_reality, :string, default: 'No Experience'
    change_column :skills, :arduino, :string, default: 'No Experience'
    change_column :skills, :embroidery, :string, default: 'No Experience'
  end

  def down
    change_column :skills, :printing, :string
    change_column :skills, :laser_cutting, :string
    change_column :skills, :virtual_reality, :string
    change_column :skills, :arduino, :string
    change_column :skills, :embroidery, :string
  end
end
