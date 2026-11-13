# A membership row starts as an unpaid checkout. The model has always defaulted new rows to pending; the column
# default said paid, so a row inserted without a status (raw SQL, insert_all) would count as a paid membership.
# Only the column default changes: no existing row is read or written.
class ChangeMembershipsStatusDefaultToPending < ActiveRecord::Migration[8.1]
  def change
    change_column_default :memberships, :status, from: "paid", to: "pending"
  end
end
