# frozen_string_literal: true

class HowHeardAboutUs < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :how_heard_about_us, :string
  end
end
