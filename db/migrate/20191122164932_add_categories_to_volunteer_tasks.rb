# frozen_string_literal: true

class AddCategoriesToVolunteerTasks < ActiveRecord::Migration[5.0]
  def change
    add_column :volunteer_tasks, :category, :string, default: 'Other'
  end
end
