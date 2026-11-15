# frozen_string_literal: true

# The payments ledger: one row per payment a provider reported, and one reversal row for a payment that was
# reversed, pointing at it. A reversal carries the provider and provider_ref of the payment it reverses, so the
# (provider, provider_ref) key is unique among payments, and a payment has at most one reversal.
#
# A reversal's reference is one composite foreign key: (reversed_entry_id, provider, provider_ref,
# reversed_entry_kind) must match (id, provider, provider_ref, kind) of an existing row. reversed_entry_kind is a
# stored generated column, 'payment' whenever reversed_entry_id is set, so the target must be a payment with the
# same provider and provider_ref. A foreign key cannot target the partial payments index, so it targets a full
# unique index on (id, provider, provider_ref, kind); it is unique because id is.
#
# Append-only: a trigger refuses every UPDATE, DELETE and TRUNCATE. A correction is a new row. down removes the
# triggers, their function and the table.
class CreatePaymentLedgerEntries < ActiveRecord::Migration[8.1]
  FUNCTION = "payment_ledger_entries_append_only"
  REVERSAL_COLUMNS = %i[reversed_entry_id provider provider_ref reversed_entry_kind].freeze
  TARGET_COLUMNS = %i[id provider provider_ref kind].freeze

  def up
    create_table :payment_ledger_entries do |t|
      t.string :provider, null: false
      t.string :provider_ref, null: false
      t.decimal :amount, precision: 10, scale: 2
      t.string :kind, null: false
      t.references :reversed_entry, index: { unique: true }
      t.virtual :reversed_entry_kind, type: :string, stored: true,
                                      as: "CASE WHEN reversed_entry_id IS NOT NULL THEN 'payment' END"
      t.timestamps

      t.index %i[id provider provider_ref kind], unique: true, name: "index_payment_ledger_entries_reversal_target"

      t.index %i[provider provider_ref], unique: true, where: "kind = 'payment'",
                                         name: "index_payment_ledger_entries_one_payment_per_provider_ref"
      t.check_constraint "kind IN ('payment', 'reversal')", name: "payment_ledger_entries_kind_check"
      t.check_constraint "(kind = 'reversal') = (reversed_entry_id IS NOT NULL)",
                         name: "payment_ledger_entries_reversal_has_entry_check"
      t.check_constraint "amount IS NULL OR amount >= 0", name: "payment_ledger_entries_amount_check"
    end

    add_foreign_key :payment_ledger_entries, :payment_ledger_entries,
                    column: REVERSAL_COLUMNS, primary_key: TARGET_COLUMNS, name: "fk_payment_ledger_entries_reversed_entry"

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
