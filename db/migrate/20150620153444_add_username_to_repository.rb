# frozen_string_literal: true

class AddUsernameToRepository < ActiveRecord::Migration
  def change
    add_column :repositories, :user_username, :string
  end
end
