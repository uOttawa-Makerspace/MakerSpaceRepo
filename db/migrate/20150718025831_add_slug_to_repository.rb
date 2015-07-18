class AddSlugToRepository < ActiveRecord::Migration
  def change
    add_column :repositories, :slug, :string
  end
end
