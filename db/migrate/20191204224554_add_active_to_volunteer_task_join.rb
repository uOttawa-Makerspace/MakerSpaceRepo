# frozen_string_literal: true

class AddActiveToVolunteerTaskJoin < ActiveRecord::Migration
  def change
    add_column :volunteer_task_joins, :active, :boolean, default: true
  end
end
