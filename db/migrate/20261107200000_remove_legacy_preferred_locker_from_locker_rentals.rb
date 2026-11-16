# Drops the old free-text column locker_rentals.preferred_locker. It shadowed the preferred_locker association
# (the link is preferred_locker_id, which stays) and was empty in every row when it was checked.
#
# The migration refuses to run, changing nothing, if any row holds a value, so no stored text is ever lost.
# down re-adds the column as it was: a nullable string with no default.
class RemoveLegacyPreferredLockerFromLockerRentals < ActiveRecord::Migration[8.1]
  def up
    filled = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM locker_rentals WHERE preferred_locker IS NOT NULL AND preferred_locker <> ''
    SQL
    if filled.positive?
      raise "locker_rentals.preferred_locker holds text in #{filled} row(s); nothing was changed. " \
            "Copy that text somewhere safe and clear it first."
    end

    remove_column :locker_rentals, :preferred_locker
  end

  def down
    add_column :locker_rentals, :preferred_locker, :string
  end
end
