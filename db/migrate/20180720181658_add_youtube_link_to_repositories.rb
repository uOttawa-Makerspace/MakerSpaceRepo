class AddYoutubeLinkToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :youtube_link, :string
  end
end
