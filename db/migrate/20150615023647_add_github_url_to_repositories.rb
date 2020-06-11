# frozen_string_literal: true

class AddGithubUrlToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :github_url, :string
  end
end
