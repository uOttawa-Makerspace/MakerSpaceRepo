# frozen_string_literal: true

class ChangeColunmOfVolunteerTaskJoin < ActiveRecord::Migration[5.0]
  def self.up
    rename_column :volunteer_task_joins, :type, :user_type
  end

  def self.down; end
end
