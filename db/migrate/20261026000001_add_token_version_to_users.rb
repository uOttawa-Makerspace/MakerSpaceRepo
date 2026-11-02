# JWTs carry the user's token_version as `ver`; bumping it (password
# change/reset, admin lock) revokes every token and cookie session issued
# before. Additive and reversible; tokens minted before this deploy carry no
# `ver` and count as version 0.
#
# Backfill: an admin lock now revokes sessions by bumping token_version, so
# users who are ALREADY admin-locked when this runs get the bump too (their
# live sessions/JWTs would otherwise survive until expiry). Admin-locked =
# locked with no end, or an end more than one day ahead (a brute-force lockout
# lasts 5 minutes; the wide margin tolerates clock skew), i.e. the complement of
# User#timed_lockout?, whose threshold (User::TIMED_LOCKOUT_CEILING, 1 day) this
# matches.
# Written in SQL so the migration does not depend on the model. Only rows still
# at version 0 are touched, so running the backfill again changes nothing, and
# `down` drops the column, so no separate reversal is needed.
class AddTokenVersionToUsers < ActiveRecord::Migration[8.1]
  TIMED_LOCKOUT_CEILING = "1 day"

  def up
    add_column :users, :token_version, :integer, null: false, default: 0
    backfill_admin_locked_users
  end

  def down
    remove_column :users, :token_version
  end

  def backfill_admin_locked_users
    execute <<~SQL.squish
      UPDATE users
      SET token_version = token_version + 1
      WHERE token_version = 0
        AND locked = TRUE
        AND (locked_until IS NULL OR locked_until > now() + interval '#{TIMED_LOCKOUT_CEILING}')
    SQL
  end
end
