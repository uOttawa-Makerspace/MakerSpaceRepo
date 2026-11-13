require Rails.root.join("lib/unique_index_guard")

# A locker belongs to at most one rental that is awaiting payment or active. The model validated this, which
# two simultaneous assignments could both pass. If duplicates exist the migration stops and lists them; it
# never removes rows.
class AddUniqueIndexToLockerRentalsReservedLocker < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_locker_rentals_on_locker_id_reserved"

  def up
    add_unique_index_concurrently :locker_rentals, :locker_id, name: INDEX_NAME,
                                  where: "state IN ('await_payment', 'active')"
  end

  def down
    remove_unique_index_concurrently :locker_rentals, name: INDEX_NAME
  end
end
