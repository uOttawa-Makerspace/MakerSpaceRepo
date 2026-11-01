# One row per Shopify order that paid a locker rental. A payment is an immutable fact; whether it
# was applied to the rental is its own status (applied | held | refunded | dismissed), so a payment
# that could not be applied (renter deactivated or deleted, rental cancelled, rental not activatable)
# stays visible to staff until they resolve it, whatever happens to the renter or the rental later.
#
# shopify_order_id is the idempotency key (INSERT ... ON CONFLICT DO NOTHING). No backfill: legacy
# locker_rentals.paid_at values have no Shopify order id. No dependent delete: payment data is kept.
class CreateLockerPayments < ActiveRecord::Migration[8.1]
  def change
    create_table :locker_payments do |t|
      t.references :locker_rental, null: false, foreign_key: true
      t.string :shopify_order_id, null: false
      t.datetime :paid_at, null: false
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency
      t.string :status, null: false
      t.string :hold_reason
      t.datetime :resolved_at
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.string :resolution_note
      t.timestamps

      t.index :shopify_order_id, unique: true
      t.index :locker_rental_id, where: "status = 'held'", name: "index_locker_payments_held_on_locker_rental_id"

      t.check_constraint "status IN ('applied', 'held', 'refunded', 'dismissed')", name: "locker_payments_status_check"
      t.check_constraint "hold_reason IS NULL OR hold_reason IN ('renter_ineligible', 'rental_cancelled', 'not_activatable')",
                         name: "locker_payments_hold_reason_check"
      t.check_constraint "status <> 'held' OR hold_reason IS NOT NULL", name: "locker_payments_held_has_reason_check"
      t.check_constraint "(status = 'held') = (resolved_at IS NULL)", name: "locker_payments_resolved_unless_held_check"
    end
  end
end
