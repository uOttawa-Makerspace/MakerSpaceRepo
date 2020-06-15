# frozen_string_literal: true

class AddYoutubeLinkToRepositories < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :youtube_link, :string
  end
end
