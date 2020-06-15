# frozen_string_literal: true

class AddSpaceIdToVolunteerTask < ActiveRecord::Migration[5.0]
  def change
    add_column :volunteer_tasks, :space_id, :integer
  end
end
