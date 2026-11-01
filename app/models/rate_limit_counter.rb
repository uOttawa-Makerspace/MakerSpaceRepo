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

  # Forget a key (a correct re-authentication clears its failure count).
  def self.reset(key)
    where(key: key.to_s).delete_all
  end

  # Deletes the rows whose window has ended, PRUNE_BATCH at a time (oldest first). Returns the
  # number deleted. Candidates are picked first; the DELETE then re-checks expiry on the rows
  # themselves, because an increment may restart a candidate's window after it was picked and must not
  # lose its (live) counter, or an attacker's budget would reset mid-window. A batch can therefore
  # delete fewer rows than it picked, even none (all revived), so the loop ends only when no expired
  # candidate is left. It terminates: `now` is fixed, a revived row leaves the candidate set, and a
  # deleted one is gone, so every pass shrinks the expired set.
  def self.prune!(now: Time.current)
    total = 0
    loop do
      keys = where(expires_at: ...now).order(:expires_at).limit(PRUNE_BATCH).pluck(:key)
      return total if keys.empty?

      total += where(key: keys, expires_at: ...now).delete_all
    end
  end
end
