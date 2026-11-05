# frozen_string_literal: true

# Solid Cache's table (Rails.cache in production and staging), in the primary
# database: no extra database to create. The columns and indexes are the ones
# solid_cache's own install template defines (cache_schema.rb). New table,
# reversible. Needs owner approval before it runs in production.
class CreateSolidCacheEntries < ActiveRecord::Migration[8.1]
  def change
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
