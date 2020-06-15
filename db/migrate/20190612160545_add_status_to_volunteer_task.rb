# frozen_string_literal: true

class AddStatusToVolunteerTask < ActiveRecord::Migration[5.0]
  def change
    add_column :volunteer_tasks, :status, :string, default: 'open'
  end
end
