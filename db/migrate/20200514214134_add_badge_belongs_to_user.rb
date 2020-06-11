# frozen_string_literal: true

class AddBadgeBelongsToUser < ActiveRecord::Migration[5.0]
  def change
    change_table :badges do |t|
      t.belongs_to :user
    end
  end
end
