# Deactivation (cannot sign in, every credential revoked) gets its own column.
# `users.active` is the legacy 2021-22 dormancy snapshot (a retired monthly job set it to
# false for users not seen in a year; it never blocked sign-in) and keeps its data, but
# nothing writes it any more and no auth rule reads it. NULL = not deactivated, for
# everyone: no default, no backfill. No index: the only readers are primary-key lookups
# (eligibility) and usable_admins, which filters the few role = 'admin' rows.
class AddDeactivatedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deactivated_at, :datetime
  end
end
