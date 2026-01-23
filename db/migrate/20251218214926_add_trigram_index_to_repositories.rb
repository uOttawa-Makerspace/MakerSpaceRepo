class AddTrigramIndexToRepositories < ActiveRecord::Migration[7.2]
  def change
    enable_extension :pg_trgm

    change_table :repositories do |t|
      t.index :title, opclass: :gin_trgm_ops, using: :gin
      t.index :description, opclass: :gin_trgm_ops, using: :gin
      t.index :category, opclass: :gin_trgm_ops, using: :gin
    end
  end
end
