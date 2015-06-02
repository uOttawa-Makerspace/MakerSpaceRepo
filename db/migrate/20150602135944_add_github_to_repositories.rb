class AddGithubToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :github, :string
  end
end
