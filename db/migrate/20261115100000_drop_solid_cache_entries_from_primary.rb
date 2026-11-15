# frozen_string_literal: true

# Solid Cache now keeps its entries in a cache database of its own
# (config/cache.yml, config/database.yml), so the solid_cache_entries table in
# the primary database is no longer read or written. Its rows are cache: the
# app rebuilds them on demand and they are never restored. The owner approved
# removing this table on 2026-11-15.
#
# down recreates the table empty, with the columns, limits and indexes of
# 20261031000002_create_solid_cache_entries. Cached rows are not restored,
# because they are cache.
class DropSolidCacheEntriesFromPrimary < ActiveRecord::Migration[8.1]
  def up
    drop_table :solid_cache_entries
  end

  def down
    create_table :solid_cache_entries do |t|
      t.binary :key, limit: 1024, null: false
      t.binary :value, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.bigint :key_hash, null: false
      t.integer :byte_size, null: false

      t.index :byte_size
      t.index %i[key_hash byte_size]
      t.index :key_hash, unique: true
    end
  end
end
