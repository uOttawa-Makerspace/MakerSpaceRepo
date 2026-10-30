# frozen_string_literal: true

# The store behind every ActionController rate_limit (see RateLimitStore), and
# the re-authentication attempt counter. rate_limit only calls
# increment(key, 1, expires_in:) and compares the returned count. Solid Cache's
# increment cannot do that atomically: it locks the key's row with SELECT ... FOR
# UPDATE, which locks nothing while the key has no row, so a parallel burst on a
# fresh key all gets 1. Here every increment is one INSERT ... ON CONFLICT DO
# UPDATE ... RETURNING: atomic in the database, shared by every worker. A window
# that has expired is restarted by the next increment; prune! (recurring) removes
# the windows nobody came back to.
class RateLimitCounter < ApplicationRecord
  PRUNE_BATCH = 1_000

  UPSERT = <<~SQL
    INSERT INTO rate_limit_counters (key, count, expires_at) VALUES (:key, :amount, :expires_at)
    ON CONFLICT (key) DO UPDATE SET
      count = CASE WHEN rate_limit_counters.expires_at <= :now THEN EXCLUDED.count
                   ELSE rate_limit_counters.count + EXCLUDED.count END,
      expires_at = CASE WHEN rate_limit_counters.expires_at <= :now THEN EXCLUDED.expires_at
                        ELSE rate_limit_counters.expires_at END
    RETURNING count
  SQL

  def self.increment(key, amount = 1, expires_in:)
    now = Time.current
    binds = { key: key.to_s, amount: Integer(amount), expires_at: now + expires_in, now: now }
    uncached { connection.select_value(sanitize_sql_array([UPSERT, binds])) }.to_i
  end

  # Counts one attempt on `key` and, in the SAME statement, ends the user's every
  # credential when that attempt is over `max`: users.token_version is the one value
  # every cookie session, access token, refresh token and websocket handshake is
  # checked against, so the bump alone revokes. The count and the bump commit or fail
  # together: an error leaves no "counted but not revoked" state, and the caller
  # lets it propagate before any password is checked (fail closed). The bump is
  # compare-and-set on `token_version`, so of any number of racing over-limit
  # requests exactly one changes the row.
  #
  # Returns [count, new_token_version]; new_token_version is nil unless THIS call
  # bumped (under the limit, already bumped by another request, or no such user).
  def self.increment_revoking(key, user_id:, token_version:, max:, expires_in:)
    now = Time.current
    binds = { key: key.to_s, amount: 1, expires_at: now + expires_in, now: now,
              user_id: user_id, token_version: token_version, max: max }
    sql = sanitize_sql_array([<<~SQL, binds])
      WITH c AS (#{UPSERT.chomp}),
      u AS (
        UPDATE users SET token_version = token_version + 1, updated_at = :now
        WHERE id = :user_id AND token_version = :token_version AND (SELECT count FROM c) > :max
        RETURNING token_version
      )
      SELECT (SELECT count FROM c) AS count, (SELECT token_version FROM u) AS new_version
    SQL
    row = uncached { connection.select_one(sql) }
    [row["count"].to_i, row["new_version"]&.to_i]
  end

  # Forget a key (a correct re-authentication clears its failure count).
  def self.reset(key)
    where(key: key.to_s).delete_all
  end

  # Deletes the rows whose window has ended, PRUNE_BATCH at a time. Returns the
  # number deleted.
  def self.prune!(now: Time.current)
    total = 0
    loop do
      deleted = where(key: where(expires_at: ...now).limit(PRUNE_BATCH).select(:key)).delete_all
      total += deleted
      return total if deleted < PRUNE_BATCH
    end
  end
end
