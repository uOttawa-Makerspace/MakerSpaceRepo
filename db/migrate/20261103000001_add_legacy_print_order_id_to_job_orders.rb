# Provenance of the print orders imported as job orders (20261103000005): the id of the
# print_orders row an order came from. NULL for every order created in the app. The
# import is idempotent through it (one job order per print order) and it is what a
# rollback of the import selects on. Unique, so a print order can never be imported twice
# even by two concurrent runs. No foreign key: print_orders is a legacy table that is
# dropped in a later migration, and the id then stays as a plain record of origin.
class AddLegacyPrintOrderIdToJobOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :job_orders, :legacy_print_order_id, :bigint
    add_index :job_orders, :legacy_print_order_id, unique: true
  end
end
