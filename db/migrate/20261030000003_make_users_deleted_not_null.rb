# Every query on users assumes deleted is true or false (`deleted = false`,
# AuthEligibility, the token_version compare-and-set), but the column was nullable
# with no default, so a NULL row would silently match neither. Backfill NULL to
# false (production has none), then default false and NOT NULL.
# Reversible: down restores the nullable, default-less column.
class MakeUsersDeletedNotNull < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :deleted, from: nil, to: false
    change_column_null :users, :deleted, false, false
  end
end
