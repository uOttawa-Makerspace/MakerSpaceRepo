# frozen_string_literal: true

class AddDescriptionToUsers < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :description, :text
    add_column :users, :email, :string
  end
end
