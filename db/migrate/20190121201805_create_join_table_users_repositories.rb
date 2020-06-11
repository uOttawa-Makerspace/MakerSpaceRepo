# frozen_string_literal: true

class CreateJoinTableUsersRepositories < ActiveRecord::Migration
  def change
    create_join_table :users, :repositories do |t|
      # t.index [:user_id, :repository_id]
      # t.index [:repository_id, :user_id]
    end
  end
end
