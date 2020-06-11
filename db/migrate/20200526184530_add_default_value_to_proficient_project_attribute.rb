# frozen_string_literal: true

class AddDefaultValueToProficientProjectAttribute < ActiveRecord::Migration
  def up
    change_column :proficient_projects, :cc, :integer, default: 0
  end

  def down
    change_column :proficient_projects, :cc, :integer, default: nil
  end
end
