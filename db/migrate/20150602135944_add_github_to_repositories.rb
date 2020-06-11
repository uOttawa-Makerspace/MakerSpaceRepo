# frozen_string_literal: true

class AddGithubToRepositories < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :github, :string
  end
end
