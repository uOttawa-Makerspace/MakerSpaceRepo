# frozen_string_literal: true

class AddSlugToRepository < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :slug, :string
  end
end
