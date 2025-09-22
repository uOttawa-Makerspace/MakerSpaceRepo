class AddTrigramIndexToUsers < ActiveRecord::Migration[7.2]
  def change
    # Postgres Trigram search module.
    # https://www.postgresql.org/docs/current/pgtrgm.html
    enable_extension :pg_trgm

    change_table :users do |t|
      # Difference between GIN and GIST indexes:
      # https://www.postgresql.org/docs/current/textsearch-indexes.html
      t.index :name, opclass: :gin_trgm_ops, using: :gin
      t.index :username, opclass: :gin_trgm_ops, using: :gin
    end
  end
end
