# frozen_string_literal: true

# One row per payment request sent to a provider (a Shopify draft order today): who it is for (a polymorphic
# reference, a locker rental first), the term it pays for, the provider and its id there, and whether it is still
# open, was paid, or was voided. Additive: nothing reads it yet. A reference has at most one open checkout.
class CreatePaymentCheckouts < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_checkouts do |t|
      t.references :reference, polymorphic: true, null: false
      t.date :term
      t.string :provider, null: false
      t.string :provider_id, null: false
      t.string :status, null: false, default: "open"
      t.timestamps

      t.index %i[provider provider_id], unique: true
      t.index %i[reference_type reference_id], unique: true, where: "status = 'open'",
                                               name: "index_payment_checkouts_one_open_per_reference"
      t.check_constraint "status IN ('open', 'paid', 'void')", name: "payment_checkouts_status_check"
    end
  end
end
