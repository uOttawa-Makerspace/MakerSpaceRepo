# frozen_string_literal: true

# A checkout is claimed in the database before the provider is asked for it: the claim is the reference's one open
# checkout, and it has no provider id until the provider's draft exists. A paid checkout always names what was paid.
# Additive: no row changes.
class AllowClaimedPaymentCheckouts < ActiveRecord::Migration[8.1]
  CHECK = "payment_checkouts_paid_has_provider_id_check"

  def up
    change_column_null :payment_checkouts, :provider_id, true
    add_check_constraint :payment_checkouts, "status <> 'paid' OR provider_id IS NOT NULL", name: CHECK
  end

  # Refuses while any checkout has no provider id: putting NOT NULL back would have to delete or invent them.
  def down
    unnamed = select_value("SELECT COUNT(*) FROM payment_checkouts WHERE provider_id IS NULL").to_i
    if unnamed.positive?
      raise "payment_checkouts holds #{unnamed} checkouts without a provider id; settle them before rolling back, nothing was changed"
    end

    remove_check_constraint :payment_checkouts, name: CHECK
    change_column_null :payment_checkouts, :provider_id, false
  end
end
