# frozen_string_literal: true

class AddCategoriesToVolunteerTasks < ActiveRecord::Migration
  def change
    add_column :volunteer_tasks, :category, :string, default: 'Other'
  end
end
