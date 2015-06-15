class AddGithubUrlToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :github_url, :string
  end
end
