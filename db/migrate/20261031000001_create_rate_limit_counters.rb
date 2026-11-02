# frozen_string_literal: true

# Atomic counters for ActionController rate_limit (RateLimitCounter, used as its
# `store:`). One row per rate-limit key; an expired window is restarted in place
# by the next increment, and RateLimitCounter.prune! (recurring) deletes rows
# whose window ended, so the table stays bounded although keys are per IP.
# Solid Cache is the app cache but its increment cannot be atomic for a key that
# has no row yet (SELECT ... FOR UPDATE locks nothing), so a parallel burst on a
# fresh key would all count 1. New table, reversible.
class CreateRateLimitCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :rate_limit_counters, id: false do |t|
      t.string :key, null: false, primary_key: true
      t.integer :count, null: false, default: 0
      t.datetime :expires_at, null: false, index: true
    end
  end
end
