# frozen_string_literal: true

class CreateJoinTableUsersProficientProjects < ActiveRecord::Migration
  def change
    create_join_table :users, :proficient_projects do |t|
      # t.index [:user_id, :proficient_project_id]
      # t.index [:proficient_project_id, :user_id]
    end
  end
end
