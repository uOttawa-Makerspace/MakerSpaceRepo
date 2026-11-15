# frozen_string_literal: true

class LockerRental
  # The rental's payment checkout records (PaymentCheckout), written beside the stored Shopify draft id, which stays
  # what every decision reads. Each writer is called by the code that changes the draft id, in the same transaction:
  # storing a draft opens its checkout, forgetting a draft closes its checkout (void when Shopify deleted it or no
  # longer has it, paid when it was paid), and an applied payment marks the stored draft's checkout paid.
  # LockerRental::PaymentRecordsCheck reports any difference between the two.
  module CheckoutRecords
    extend ActiveSupport::Concern

    PROVIDER = Payments::ShopifyAdapter::PROVIDER

    included do
      has_many :payment_checkouts, as: :reference, inverse_of: :reference
    end

    # The stored draft `gid` is now the rental's invoice: its open checkout, for the term the rental ends. A rental
    # has one open checkout, so one it had for another draft is voided first (that draft was replaced).
    def open_checkout_record(gid)
      payment_checkouts.open.where.not(provider_id: gid).update_all(status: 'void', updated_at: Time.current)
      payment_checkouts.create!(provider: PROVIDER, provider_id: gid, term: checkout_term, status: :open)
    end

    # The open checkout of draft `gid`, if there is one, is closed as `status` ('void' or 'paid').
    def close_checkout_record(gid, status)
      checkout_records_of(gid).open.update_all(status: status.to_s, updated_at: Time.current)
    end

    # A payment was applied to the rental: the open checkout of its stored draft is paid, for the term the rental
    # now ends.
    def record_checkout_paid
      return if shopify_draft_order_id.blank?

      checkout_records_of(shopify_draft_order_id).open
                                                 .update_all(status: 'paid', term: checkout_term, updated_at: Time.current)
    end

    # Whether the stored draft `gid` has no checkout record and the rental's own data does not settle its status
    # (only a rental awaiting payment, or active with a paid_at, does: open or paid).
    def unsettled_draft?(gid)
      shopify_draft_order_id == gid && !(await_payment? || (active? && paid_at.present?)) && checkout_records_of(gid).none?
    end

    private

    def checkout_records_of(gid) = payment_checkouts.where(provider: PROVIDER, provider_id: gid)

    def checkout_term = owned_until&.to_date
  end
end
