# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[5.0]
  def change
    create_table :comments do |t|
      t.references :user, index: true, foreign_key: true
      t.references :repository, index: true, foreign_key: true
      t.text :content
      t.integer :upvote, default: 0

      t.timestamps null: false
    end
  end
end
