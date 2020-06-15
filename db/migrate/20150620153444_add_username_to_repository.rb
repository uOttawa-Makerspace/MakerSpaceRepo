# frozen_string_literal: true

class AddUsernameToRepository < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :user_username, :string
  end
end
