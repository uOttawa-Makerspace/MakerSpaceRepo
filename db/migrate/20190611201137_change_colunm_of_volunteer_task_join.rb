# frozen_string_literal: true

class ChangeColunmOfVolunteerTaskJoin < ActiveRecord::Migration
  def self.up
    rename_column :volunteer_task_joins, :type, :user_type
  end

  def self.down; end
end
