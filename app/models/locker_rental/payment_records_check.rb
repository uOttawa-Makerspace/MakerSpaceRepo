# frozen_string_literal: true

class LockerRental
  # Compares what every locker decision still reads (the rentals' stored Shopify draft ids, the locker_payments rows)
  # with the payment checkout records and the payments ledger written beside them, and reports each kind of
  # difference once per run through Rails.error.report, with row ids only. Run by LockerPaymentRecordsCheckJob.
  #
  # It changes nothing, with one exception: a stored draft whose status the rental's own data does not settle (any
  # rental with a draft that is neither awaiting payment nor active with a paid_at) and that has no checkout record
  # yet is looked up at Shopify through the adapter. Its checkout is recorded only for a clear answer (paid, open, or
  # gone: void), under the rental's row lock and only while the rental still stores that draft; any other answer is
  # reported.
  class PaymentRecordsCheck
    # Raised only to be reported: the old columns and the new records differ.
    class Difference < StandardError; end

    MAX_IDS = 100
    RECORDED_STATUS = { paid: 'paid', open: 'open', gone: 'void' }.freeze
    REFERENCE_TYPE = LockerRental.polymorphic_name
    PROVIDER = CheckoutRecords::PROVIDER
    SETTLED = CheckoutRecords::DRAFT_STATUS_SETTLED_SQL

    # The stored draft's checkout record (alias c) of the outer locker_rentals row.
    CHECKOUT_OF_STORED_DRAFT = <<~SQL.squish
      c.reference_type = '#{REFERENCE_TYPE}' AND c.reference_id = locker_rentals.id AND c.provider = '#{PROVIDER}'
      AND c.provider_id = locker_rentals.shopify_draft_order_id
    SQL

    # check name => the query of the ids that differ
    CHECKS = {
      # rental ids: a stored draft the rental's data settles, without a checkout record
      'checkout_missing' => <<~SQL.squish,
        SELECT locker_rentals.id FROM locker_rentals
        WHERE locker_rentals.shopify_draft_order_id IS NOT NULL AND #{SETTLED}
          AND NOT EXISTS (SELECT 1 FROM payment_checkouts c WHERE #{CHECKOUT_OF_STORED_DRAFT})
        ORDER BY locker_rentals.id
      SQL
      # checkout ids: the stored draft's checkout is not open while the rental awaits payment, or not paid while it is
      # active with a paid_at
      'checkout_status_differs' => <<~SQL.squish,
        SELECT c.id FROM locker_rentals JOIN payment_checkouts c ON #{CHECKOUT_OF_STORED_DRAFT}
        WHERE #{SETTLED} AND c.status <> CASE locker_rentals.state WHEN 'await_payment' THEN 'open' ELSE 'paid' END
        ORDER BY c.id
      SQL
      # checkout ids: an open checkout of a draft its rental does not store (or of a rental that is gone)
      'open_checkout_not_stored' => <<~SQL.squish,
        SELECT c.id FROM payment_checkouts c LEFT JOIN locker_rentals ON locker_rentals.id = c.reference_id
        WHERE c.reference_type = '#{REFERENCE_TYPE}' AND c.status = 'open'
          AND locker_rentals.shopify_draft_order_id IS DISTINCT FROM c.provider_id
        ORDER BY c.id
      SQL
      # locker payment ids: no ledger entry
      'ledger_entry_missing' => <<~SQL.squish,
        SELECT lp.id FROM locker_payments lp WHERE lp.ledger_entry_id IS NULL ORDER BY lp.id
      SQL
      # locker payment ids: the linked entry is not this payment's (kind, provider, order id or amount)
      'ledger_entry_differs' => <<~SQL.squish,
        SELECT lp.id FROM locker_payments lp JOIN payment_ledger_entries e ON e.id = lp.ledger_entry_id
        WHERE e.kind <> 'payment' OR e.provider <> '#{PROVIDER}' OR e.provider_ref <> lp.shopify_order_id
           OR e.amount IS DISTINCT FROM lp.amount
        ORDER BY lp.id
      SQL
      # locker payment ids: refunded without a reversal entry or reversed_at, or one of those without the refund
      'reversal_differs' => <<~SQL.squish
        SELECT lp.id FROM locker_payments lp
        WHERE (lp.status = 'refunded') <> (lp.reversed_at IS NOT NULL)
           OR (lp.status = 'refunded') <> EXISTS (
                SELECT 1 FROM payment_ledger_entries v WHERE v.reversed_entry_id = lp.ledger_entry_id)
        ORDER BY lp.id
      SQL
    }.freeze

    def self.run(adapter: Payments::ShopifyAdapter.new) = new(adapter).run

    def initialize(adapter)
      @adapter = adapter
    end

    # Reports the differences first (database only), then records the drafts Shopify settles, so a Shopify failure
    # never stops the comparison from being reported. Returns { check name => ids } of what it reported.
    def run
      found = report_all(CHECKS.transform_values { |sql| connection.select_values(sql) })
      found.merge(report_all('checkout_status_unclear' => record_unrecorded_checkouts))
    end

    private

    def connection = LockerRental.connection

    # The rental ids whose draft could not be recorded.
    def record_unrecorded_checkouts
      LockerRental.with_unrecorded_draft_status.order(:id).pluck(:id, :shopify_draft_order_id).reject do |rental_id, gid|
        status = RECORDED_STATUS[@adapter.checkout_status(gid)]
        status && record_checkout(rental_id, gid, status)
      end.map(&:first)
    end

    # Under the row lock, only while the rental still stores `gid` without a checkout record and its data still does
    # not settle it (a rental changed since is looked at again next run). An open checkout is recorded the way a
    # stored draft opens one (#open_checkout_record: any other open checkout of the rental is voided first, one open
    # checkout per rental). True when recorded or no longer due.
    def record_checkout(rental_id, gid, status)
      LockerRental.transaction do
        rental = LockerRental.with_unrecorded_draft_status.lock.find_by(id: rental_id, shopify_draft_order_id: gid)
        next true unless rental
        next rental.open_checkout_record(gid) if status == 'open'

        LockerRental.insert_checkout_record(rental_id, gid, status: status, term: rental.owned_until&.to_date)
      end
    end

    def report_all(found)
      found.reject { |_, ids| ids.empty? }.each { |name, ids| report(name, ids) }
    end

    def report(name, ids)
      Rails.error.report(
        Difference.new("locker payment records differ: #{name}"),
        handled: true, severity: :error, context: { check: name, count: ids.size, ids: ids.first(MAX_IDS) }
      )
    end
  end
end
