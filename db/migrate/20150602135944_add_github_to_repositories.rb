# frozen_string_literal: true

class AddGithubToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :github, :string
  end
end
