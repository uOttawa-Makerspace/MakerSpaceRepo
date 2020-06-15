# frozen_string_literal: true

class AddMakeIdToRepository < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :make_id, :integer
  end
end
