# frozen_string_literal: true

class LockerRental
  # The rental's payment checkout records (PaymentCheckout), written beside the stored Shopify draft id, which stays
  # what every decision reads. Each step is called explicitly by the code that changes the draft id, in the same
  # transaction: a stored draft opens its checkout, a draft deleted (or gone) at Shopify voids it, a draft found paid
  # pays it, and an applied payment pays the stored draft's checkout.
  #
  # The writes never raise on a row that is already there (an INSERT ... ON CONFLICT DO NOTHING on the provider id, and
  # conditional UPDATEs), so a checkout record cannot fail the payment or the draft it shadows; a write that changed
  # nothing leaves a difference LockerRental::PaymentRecordsCheck reports.
  module CheckoutRecords
    extend ActiveSupport::Concern

    PROVIDER = Payments::ShopifyAdapter::PROVIDER
    PROVIDER_ID_INDEX = :index_payment_checkouts_on_provider_and_provider_id

    # The one rule for which rentals' own data tells their stored draft's checkout status: a rental awaiting payment
    # (open) or active with a paid_at (paid). Any other stored draft's status is known only at Shopify.
    DRAFT_STATUS_SETTLED_SQL = <<~SQL.squish
      (locker_rentals.state = 'await_payment' OR (locker_rentals.state = 'active' AND locker_rentals.paid_at IS NOT NULL))
    SQL

    included do
      has_many :payment_checkouts, as: :reference, inverse_of: :reference

      # Rentals storing a draft the rental's own data does not settle, with no checkout record for it yet.
      scope :with_unrecorded_draft_status, lambda {
        where.not(shopify_draft_order_id: nil).where.not(DRAFT_STATUS_SETTLED_SQL)
             .where.not(stored_draft_checkouts.arel.exists)
      }
    end

    class_methods do
      # The checkout records of each rental's stored draft, correlated with the outer locker_rentals row.
      def stored_draft_checkouts
        PaymentCheckout.where(reference_type: polymorphic_name, provider: PROVIDER)
                       .where('payment_checkouts.reference_id = locker_rentals.id')
                       .where('payment_checkouts.provider_id = locker_rentals.shopify_draft_order_id')
      end

      # Inserts a checkout record unless the provider id already has one (ON CONFLICT DO NOTHING). True when inserted.
      def insert_checkout_record(rental_id, gid, status:, term:)
        PaymentCheckout.insert(
          { reference_type: polymorphic_name, reference_id: rental_id, provider: PROVIDER, provider_id: gid,
            status: status, term: term },
          unique_by: PROVIDER_ID_INDEX
        ).rows.any?
      end
    end

    # The stored draft `gid` is now the rental's invoice: its open checkout, for the term the rental ends. A rental
    # has one open checkout, so one it had for another draft is voided first (that draft was replaced).
    def open_checkout_record(gid)
      payment_checkouts.open.where.not(provider_id: gid).update_all(status: 'void', updated_at: Time.current)
      self.class.insert_checkout_record(id, gid, status: 'open', term: checkout_term)
    end

    # Shopify deleted the draft `gid`, or no longer has it: its open checkout is void.
    def void_checkout_record(gid)
      checkout_records_of(gid).open.update_all(status: 'void', updated_at: Time.current)
    end

    # Shopify reports the draft `gid` paid: its open checkout is paid.
    def pay_checkout_record(gid)
      checkout_records_of(gid).open.update_all(status: 'paid', updated_at: Time.current)
    end

    # A payment was applied to the rental: the open checkout of the draft the row stores now (read again, so a stale
    # instance cannot name another draft; the callers hold the row lock) is paid, for the term the rental now ends.
    def record_checkout_paid
      gid = self.class.where(id: id).pick(:shopify_draft_order_id)
      return if gid.blank?

      checkout_records_of(gid).open.update_all(status: 'paid', term: checkout_term, updated_at: Time.current)
    end

    private

    def checkout_records_of(gid) = payment_checkouts.where(provider: PROVIDER, provider_id: gid)

    def checkout_term = owned_until&.to_date
  end
end
