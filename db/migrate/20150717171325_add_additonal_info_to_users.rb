# frozen_string_literal: true

class AddAdditonalInfoToUsers < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :gender, :string
    add_column :users, :faculty, :string
    add_column :users, :use, :string
  end
end
