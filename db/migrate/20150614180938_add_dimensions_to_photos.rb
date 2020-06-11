# frozen_string_literal: true

class AddDimensionsToPhotos < ActiveRecord::Migration[5.0]
  def change
    add_column :photos, :height, :integer
    add_column :photos, :width, :integer
  end
end
