# frozen_string_literal: true

# The payments ledger: one row per payment a provider reported, and one reversal row for a payment that was
# reversed, pointing at it. A reversal carries the provider and provider_ref of the payment it reverses, so the
# (provider, provider_ref) key is unique among payments, and a payment has at most one reversal.
#
# Append-only: a trigger refuses every UPDATE, DELETE and TRUNCATE. A correction is a new row. down removes the
# triggers, their function and the table.
class CreatePaymentLedgerEntries < ActiveRecord::Migration[8.1]
  FUNCTION = "payment_ledger_entries_append_only"

  def up
    create_table :payment_ledger_entries do |t|
      t.string :provider, null: false
      t.string :provider_ref, null: false
      t.decimal :amount, precision: 10, scale: 2
      t.string :kind, null: false
      t.references :reversed_entry, foreign_key: { to_table: :payment_ledger_entries }, index: { unique: true }
      t.timestamps

      t.index %i[provider provider_ref], unique: true, where: "kind = 'payment'",
                                         name: "index_payment_ledger_entries_one_payment_per_provider_ref"
      t.check_constraint "kind IN ('payment', 'reversal')", name: "payment_ledger_entries_kind_check"
      t.check_constraint "(kind = 'reversal') = (reversed_entry_id IS NOT NULL)",
                         name: "payment_ledger_entries_reversal_has_entry_check"
      t.check_constraint "amount IS NULL OR amount >= 0", name: "payment_ledger_entries_amount_check"
    end

    execute <<~SQL
      CREATE FUNCTION #{FUNCTION}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'payment_ledger_entries is append-only: % refused', TG_OP;
      END;
      $$
    SQL
    execute <<~SQL.squish
      CREATE TRIGGER payment_ledger_entries_no_change BEFORE UPDATE OR DELETE ON payment_ledger_entries
      FOR EACH ROW EXECUTE FUNCTION #{FUNCTION}()
    SQL
    execute <<~SQL.squish
      CREATE TRIGGER payment_ledger_entries_no_truncate BEFORE TRUNCATE ON payment_ledger_entries
      FOR EACH STATEMENT EXECUTE FUNCTION #{FUNCTION}()
    SQL
  end

  def down
    drop_table :payment_ledger_entries
    execute "DROP FUNCTION #{FUNCTION}()"
  end
end
