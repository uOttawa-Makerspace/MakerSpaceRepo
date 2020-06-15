# frozen_string_literal: true

class AddGithubUrlToRepositories < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :github_url, :string
  end
end
