# frozen_string_literal: true

class AddCcToVolunteerTask < ActiveRecord::Migration
  def change
    add_column :volunteer_tasks, :cc, :integer, default: 0
  end
end
