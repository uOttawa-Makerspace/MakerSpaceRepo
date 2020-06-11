# frozen_string_literal: true

class AddDetailsToUsers < ActiveRecord::Migration
  def change
    add_column :users, :studentID, :integer
    add_column :users, :program, :string
  end
end
