class RenamePasswordColumnForRepository < ActiveRecord::Migration
  def change
    rename_column :repositories, :password, :repo_pass
  end
end
