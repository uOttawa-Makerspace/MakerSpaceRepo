# frozen_string_literal: true

class Identity < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :identity, :string
  end
end
