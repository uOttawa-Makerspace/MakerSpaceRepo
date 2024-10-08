# frozen_string_literal: true

class CreateBadges < ActiveRecord::Migration[5.0]
  def change
    create_table :badges do |t|
      t.string :user
      t.string :image_url
      t.string :issued_to
      t.string :description

      t.timestamps null: false
    end
  end
end
