# frozen_string_literal: true

# Atomic counters for ActionController rate_limit (RateLimitCounter, used as its
# `store:`). The default cache store in production is a FileStore, whose
# increment is not atomic across processes (it rewrites the file by rename, so
# concurrent workers lose updates). One row per rate-limit key; an expired
# window is restarted in place by the next increment. New table, reversible.
class CreateRateLimitCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :rate_limit_counters, id: false do |t|
      t.string :key, null: false, primary_key: true
      t.integer :count, null: false, default: 0
      t.datetime :expires_at, null: false
    end
  end
end
