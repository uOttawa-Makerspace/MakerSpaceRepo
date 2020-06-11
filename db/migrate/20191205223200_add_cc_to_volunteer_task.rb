# frozen_string_literal: true

class AddCcToVolunteerTask < ActiveRecord::Migration[5.0]
  def change
    add_column :volunteer_tasks, :cc, :integer, default: 0
  end
end
