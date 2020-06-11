# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration
  def change
    create_table :users do |t|
      t.string :username
      t.string :first_name
      t.string :last_name
      t.string :password
      t.string :url
      t.string :location

      t.timestamps null: false
    end
  end
end
