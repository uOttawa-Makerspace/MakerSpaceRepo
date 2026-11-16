# frozen_string_literal: true

# Copies the locker rentals' Shopify draft ids into payment_checkouts, only where the rental's own data settles the
# checkout's status:
# - a rental awaiting payment with a draft id: an open checkout;
# - an active rental with a draft id and a paid_at: a paid checkout.
# An active rental with a draft id but no paid_at is skipped: the database cannot tell whether that draft is open,
# paid or gone at Shopify, so it is left to be looked up there. The term is the rental's owned_until date in the
# app's time zone (owned_until is stored in UTC).
#
# Copy only: locker_rentals is not changed. The ids of the checkouts written, with the status written, are kept in
# payment_checkout_backfills, so down removes exactly those rows, and only while each still holds what was written
# (a checkout changed since is kept, and down then raises, changing nothing). Safe to run again: a draft id that
# already has a checkout is skipped.
class BackfillPaymentCheckoutsFromLockerRentals < ActiveRecord::Migration[8.1]
  TABLE = "payment_checkout_backfills"

  def up
    execute <<~SQL.squish
      CREATE TABLE IF NOT EXISTS #{TABLE} (
        payment_checkout_id bigint PRIMARY KEY,
        locker_rental_id bigint NOT NULL,
        provider_id character varying NOT NULL,
        status character varying NOT NULL,
        filled_at timestamp without time zone NOT NULL DEFAULT now()
      )
    SQL

    written = select_rows(<<~SQL.squish)
      WITH written AS (
        INSERT INTO payment_checkouts (reference_type, reference_id, term, provider, provider_id, status, created_at, updated_at)
        SELECT 'LockerRental', r.id, (r.owned_until AT TIME ZONE 'UTC' AT TIME ZONE #{zone})::date, 'shopify', r.shopify_draft_order_id,
               CASE r.state WHEN 'await_payment' THEN 'open' ELSE 'paid' END, now(), now()
        FROM locker_rentals r
        WHERE r.shopify_draft_order_id IS NOT NULL
          AND (r.state = 'await_payment' OR (r.state = 'active' AND r.paid_at IS NOT NULL))
        ORDER BY r.id
        ON CONFLICT DO NOTHING
        RETURNING id, reference_id, provider_id, status
      )
      INSERT INTO #{TABLE} (payment_checkout_id, locker_rental_id, provider_id, status)
      SELECT id, reference_id, provider_id, status FROM written
      RETURNING status
    SQL
    skipped = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM locker_rentals
      WHERE shopify_draft_order_id IS NOT NULL AND state = 'active' AND paid_at IS NULL
    SQL
    say "payment_checkouts: #{written.count { |(s)| s == 'open' }} open and #{written.count { |(s)| s == 'paid' }} " \
        "paid written; #{skipped} active rentals with a draft but no paid_at left to the Shopify check"
  end

  def down
    unless table_exists?(TABLE)
      raise "#{TABLE} is missing, so the checkouts this migration wrote are unknown; nothing was changed"
    end

    recorded = select_value("SELECT COUNT(*) FROM #{TABLE}").to_i
    removed = execute(<<~SQL.squish).cmd_tuples
      DELETE FROM payment_checkouts c USING #{TABLE} b
      WHERE c.id = b.payment_checkout_id AND c.reference_type = 'LockerRental' AND c.reference_id = b.locker_rental_id
        AND c.provider_id = b.provider_id AND c.status = b.status
    SQL
    if removed != recorded
      raise "Cannot undo the checkout backfill: removed #{removed} of #{recorded} (the others changed since or are " \
            "gone); nothing was changed and #{TABLE} was kept"
    end

    execute "DROP TABLE #{TABLE}"
  end

  private

  def zone = connection.quote(Time.zone.tzinfo.identifier)
end
