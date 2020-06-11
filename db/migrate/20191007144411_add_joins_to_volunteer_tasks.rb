# frozen_string_literal: true

class AddJoinsToVolunteerTasks < ActiveRecord::Migration
  def change
    add_column :volunteer_tasks, :joins, :integer, default: 1
  end
end
