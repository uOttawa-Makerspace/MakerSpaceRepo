# frozen_string_literal: true

class RemoveActiveFromVolunteerTask < ActiveRecord::Migration[5.0]
  def change
    remove_column :volunteer_tasks, :active
  end
end
