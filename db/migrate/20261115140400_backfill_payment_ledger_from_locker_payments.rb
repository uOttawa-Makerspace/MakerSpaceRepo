# frozen_string_literal: true

# Copies every locker payment into the payments ledger: each one (applied, held, refunded or dismissed) gets a
# payment entry with its Shopify order id and amount, created at the time the payment was recorded, and the locker
# payment points at it (ledger_entry_id). A refunded one also gets a reversal entry pointing at that payment entry,
# created at the time it was marked refunded.
#
# Copy only: no existing locker_payments column changes. The entries written, and the locker payment each one
# came from, are kept in payment_ledger_backfills, so down removes exactly those entries (the append-only trigger
# is switched off for that statement only, inside the migration's transaction) and clears exactly those links.
# down raises, changing nothing, unless every recorded row is undone. Safe to run again: a locker payment that
# already points at an entry is skipped, and a payment entry has at most one reversal.
class BackfillPaymentLedgerFromLockerPayments < ActiveRecord::Migration[8.1]
  TABLE = "payment_ledger_backfills"
  TRIGGER = "payment_ledger_entries_no_change"

  def up
    execute <<~SQL.squish
      CREATE TABLE IF NOT EXISTS #{TABLE} (
        payment_ledger_entry_id bigint PRIMARY KEY,
        locker_payment_id bigint NOT NULL,
        kind character varying NOT NULL,
        filled_at timestamp without time zone NOT NULL DEFAULT now()
      )
    SQL
    payments = copy_payments
    link_payments
    reversals = copy_reversals
    unlinked = select_value("SELECT COUNT(*) FROM locker_payments WHERE ledger_entry_id IS NULL").to_i
    say "payment_ledger_entries: #{payments} payment and #{reversals} reversal entries written from locker_payments; " \
        "#{unlinked} locker payments without an entry"
  end

  def down
    raise "#{TABLE} is missing, so the entries this migration wrote are unknown; nothing was changed" unless table_exists?(TABLE)

    unlinked = execute(<<~SQL.squish).cmd_tuples
      UPDATE locker_payments lp SET ledger_entry_id = NULL FROM #{TABLE} b
      WHERE b.kind = 'payment' AND lp.id = b.locker_payment_id AND lp.ledger_entry_id = b.payment_ledger_entry_id
    SQL
    execute "ALTER TABLE payment_ledger_entries DISABLE TRIGGER #{TRIGGER}"
    removed = remove_recorded("reversal") + remove_recorded("payment")
    execute "ALTER TABLE payment_ledger_entries ENABLE TRIGGER #{TRIGGER}"
    check_undone(unlinked, removed)
    execute "DROP TABLE #{TABLE}"
  end

  private

  def copy_payments
    execute(<<~SQL.squish).cmd_tuples
      WITH written AS (
        INSERT INTO payment_ledger_entries (provider, provider_ref, amount, kind, created_at, updated_at)
        SELECT 'shopify', lp.shopify_order_id, lp.amount, 'payment', lp.created_at, lp.created_at
        FROM locker_payments lp
        WHERE lp.ledger_entry_id IS NULL
        ORDER BY lp.id
        ON CONFLICT DO NOTHING
        RETURNING id, provider_ref
      )
      INSERT INTO #{TABLE} (payment_ledger_entry_id, locker_payment_id, kind)
      SELECT w.id, lp.id, 'payment' FROM written w JOIN locker_payments lp ON lp.shopify_order_id = w.provider_ref
    SQL
  end

  def link_payments
    execute <<~SQL.squish
      UPDATE locker_payments lp SET ledger_entry_id = b.payment_ledger_entry_id FROM #{TABLE} b
      WHERE b.kind = 'payment' AND lp.id = b.locker_payment_id AND lp.ledger_entry_id IS NULL
    SQL
  end

  def copy_reversals
    execute(<<~SQL.squish).cmd_tuples
      WITH written AS (
        INSERT INTO payment_ledger_entries (provider, provider_ref, amount, kind, reversed_entry_id, created_at, updated_at)
        SELECT e.provider, e.provider_ref, e.amount, 'reversal', e.id, lp.resolved_at, lp.resolved_at
        FROM locker_payments lp
        JOIN #{TABLE} b ON b.kind = 'payment' AND b.locker_payment_id = lp.id
        JOIN payment_ledger_entries e ON e.id = b.payment_ledger_entry_id
        WHERE lp.status = 'refunded'
        ORDER BY lp.id
        ON CONFLICT DO NOTHING
        RETURNING id, reversed_entry_id
      )
      INSERT INTO #{TABLE} (payment_ledger_entry_id, locker_payment_id, kind)
      SELECT w.id, b.locker_payment_id, 'reversal' FROM written w JOIN #{TABLE} b ON b.payment_ledger_entry_id = w.reversed_entry_id
    SQL
  end

  def remove_recorded(kind)
    execute(<<~SQL.squish).cmd_tuples
      DELETE FROM payment_ledger_entries e USING #{TABLE} b WHERE b.kind = '#{kind}' AND e.id = b.payment_ledger_entry_id
    SQL
  end

  def check_undone(unlinked, removed)
    payments, entries = select_rows("SELECT COUNT(*) FILTER (WHERE kind = 'payment'), COUNT(*) FROM #{TABLE}").first.map(&:to_i)
    return if unlinked == payments && removed == entries

    raise "Cannot undo the ledger backfill: cleared #{unlinked} of #{payments} links and removed #{removed} of " \
          "#{entries} entries (the others changed since or are gone); nothing was changed and #{TABLE} was kept"
  end
end
