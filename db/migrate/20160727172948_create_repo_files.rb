# frozen_string_literal: true

class CreateRepoFiles < ActiveRecord::Migration
  def change
    create_table :repo_files do |t|
      t.references :repository, index: true, foreign_key: true

      t.timestamps null: false
    end
  end
end
