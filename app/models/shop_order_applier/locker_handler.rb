# frozen_string_literal: true

class ShopOrderApplier
  # The locker payment of an order: paid by card (orders/paid) or in cash (orders/fulfilled).
  class LockerHandler < Handler
    def self.takes_cash? = true
    def self.metafield_key(_hook) = "locker_db_reference"

    def call
      return if left_unapplied? # the refused lookup is reported once (report_lookup_rejection)

      rental = referenced_rental
      record_payment(rental) if rental
    end

    private

    # A locker-tagged order that names no locker rental at all: nothing to apply, and not to be lost silently
    # either (staff reconcile it from the report).
    def referenced_rental
      ref = reference
      if ref.blank?
        applier.report_problem(LockerOrderWithoutReference.new("locker order #{plan.id} carries no locker_db_reference"),
                               context: { shopify_order_id: plan.id })
        return
      end

      rental = LockerRental.find_by(id: ref)
      return rental if rental

      applier.report_problem(
        UnknownLockerRental.new("locker order #{plan.id} references unknown locker rental #{ref}"),
        context: { locker_rental_id: ref.to_s, shopify_order_id: plan.id }
      )
      nil
    end

    # amount = the locker line only (nil when it cannot be told); order_total = the whole order. A malformed
    # or out-of-range figure is stored as nil and never fails the order; record_payment reports it (ids only)
    # after its commit, and only when the payment row is really new, so a replayed delivery does not report it again.
    def record_payment(rental)
      problems = []
      rental.record_payment(
        shopify_order_id: plan.id,
        paid_at: plan.event.paid_at,
        amount: safe_money(problems, "locker line amount") { rental.locker_line_amount(hook["line_items"]) },
        order_total: safe_money(problems, "order total") { LockerPayment.money(hook["total_price"]) },
        currency: hook["currency"].presence&.to_s&.first(8),
        malformed_amounts: problems
      )
    end

    def safe_money(problems, what)
      yield
    rescue ArgumentError
      problems << what
      nil
    end
  end
end
