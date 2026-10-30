# frozen_string_literal: true

# An atomic, cross-process counter store for ActionController rate_limit:
#   rate_limit ..., store: RateLimitCounter
# rate_limit only calls increment(key, 1, expires_in:) and compares the returned
# count. The default cache store in production is a FileStore (no cache_store is
# configured), whose increment rewrites the file by rename and so loses updates
# when the server's workers count at the same time. Here every increment is one
# INSERT ... ON CONFLICT DO UPDATE ... RETURNING: atomic in the database, shared
# by every worker. A window that has expired is restarted by the next increment.
# One row per key (per user for the re-authentication limit), so the table stays
# bounded without a sweep.
class RateLimitCounter < ApplicationRecord
  self.primary_key = "key"

  def self.increment(key, amount = 1, expires_in:)
    now = Time.current
    binds = { key: key.to_s, amount: Integer(amount), expires_at: now + expires_in, now: now }
    sql = sanitize_sql_array([<<~SQL, binds])
      INSERT INTO rate_limit_counters (key, count, expires_at) VALUES (:key, :amount, :expires_at)
      ON CONFLICT (key) DO UPDATE SET
        count = CASE WHEN rate_limit_counters.expires_at <= :now THEN EXCLUDED.count
                     ELSE rate_limit_counters.count + EXCLUDED.count END,
        expires_at = CASE WHEN rate_limit_counters.expires_at <= :now THEN EXCLUDED.expires_at
                          ELSE rate_limit_counters.expires_at END
      RETURNING count
    SQL
    uncached { connection.select_value(sql) }.to_i
  end
end
