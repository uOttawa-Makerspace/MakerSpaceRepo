# frozen_string_literal: true

class ChangeUserToUsername < ActiveRecord::Migration[5.0]
  def change
    rename_column :badges, :user, :username
  end
end
