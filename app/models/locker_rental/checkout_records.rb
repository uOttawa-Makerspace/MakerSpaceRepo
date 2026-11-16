# frozen_string_literal: true

class LockerRental
  # The rental's payment checkout records (PaymentCheckout). The pay link comes from the rental's one open checkout:
  # it is claimed in the database before Shopify is asked for a draft, the draft is tagged with the claim's id, and the
  # claim takes the draft's id under the row lock; a later attempt on the same claim first looks for an open draft with
  # that tag and reuses it. The stored Shopify draft id is written in step with it, and stays what the draft removal,
  # the sweep and the payment steps read. Each step is called explicitly by the code that changes the draft id or the
  # state, in the same transaction: a draft deleted (or gone) at Shopify voids its checkout, a draft found paid pays
  # it, an applied payment pays the stored draft's checkout, and a new term voids last term's open checkout.
  #
  # The writes beside a draft never raise on a row that is already there (an INSERT ... ON CONFLICT DO NOTHING on the
  # provider id, and conditional UPDATEs); a write that changed nothing leaves a difference
  # LockerRental::PaymentRecordsCheck reports.
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

    # The Shopify id of the rental's open checkout's draft; nil when it has none, or only a claim with no draft yet.
    def open_checkout_draft_id = open_checkout&.provider_id

    # Last term's open checkout (drafted or only claimed) is void once the rental starts a new term, in the
    # transaction of that save: its link is never served again, and the new term claims its own. Its draft is removed
    # at Shopify after the commit (#sync_shopify_draft_order_after_commit). Call it after the save that changed the
    # state.
    def void_last_term_checkout
      return unless started_new_term?

      payment_checkouts.open.update_all(status: 'void', updated_at: Time.current)
    end

    # The stored draft `gid` is now the rental's invoice: its open checkout, for the term the rental ends. A rental
    # has one open checkout, so one it had for another draft, or a claim with none yet, is voided first (replaced).
    def open_checkout_record(gid)
      payment_checkouts.open.where('provider_id IS DISTINCT FROM ?', gid).update_all(status: 'void', updated_at: Time.current)
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

    # A payment was applied to the rental: the open checkout of the draft it was paid through is paid, for the term the
    # rental now ends. That draft is `paid_gid` when the order named it (only that draft's checkout, never another's),
    # else the draft the row stores now (read again, so a stale instance cannot name another draft; the callers hold
    # the row lock).
    def record_checkout_paid(paid_gid = nil)
      gid = paid_gid || self.class.where(id: id).pick(:shopify_draft_order_id)
      return if gid.blank?

      checkout_records_of(gid).open.update_all(status: 'paid', term: checkout_term, updated_at: Time.current)
    end

    private

    def open_checkout = payment_checkouts.open.find_by(provider: PROVIDER)

    # The draft the pay link is served from: the open checkout's, or a stored draft no checkout record names yet.
    def checkout_draft_id = open_checkout_draft_id || adopt_unrecorded_draft

    # A stored draft no checkout record names yet (stored before checkout records were written) opens its checkout, as
    # storing it does, under the row lock while the rental may take a draft. Its Shopify id, or nil.
    def adopt_unrecorded_draft
      return unless unrecorded_draft?

      with_lock { open_unrecorded_draft if may_take_draft_order? }&.provider_id
    end

    # Under the row lock, while the rental may take a draft: the rental's open checkout, as [checkout, whether it was
    # there already]. That is the open checkout it has (another request's, or a claim an earlier attempt left), the
    # stored draft when no checkout record names it yet (it opens its checkout, as storing it does), or else a new
    # claim with no draft. nil when the rental may no longer take a draft.
    #
    # Two first views at the same moment can race: the second finds the first's claim (so it looks up the tag, and
    # Shopify may not list the first's draft yet), creates a second draft, and #take_draft discards it because the claim
    # already has the first's draft. This is tolerated: the one claim stays the only checkout the link is served from,
    # the extra draft is deleted at once (or by the hourly sweep if that delete fails), and serialising the Shopify call
    # would hold the row lock across HTTP.
    def claim_checkout
      with_lock do
        next nil unless may_take_draft_order?

        existing = open_checkout || open_unrecorded_draft
        existing ? [existing, true] : [payment_checkouts.create!(provider: PROVIDER, term: checkout_term), false]
      end
    end

    def unrecorded_draft?
      shopify_draft_order_id.present? && !PaymentCheckout.exists?(provider: PROVIDER, provider_id: shopify_draft_order_id)
    end

    # Opens the checkout of the stored draft when no checkout record names it (call it under the row lock).
    def open_unrecorded_draft
      return unless unrecorded_draft?

      open_checkout_record(shopify_draft_order_id)
      open_checkout
    end

    # Makes the claim's draft on Shopify (no lock held), tagged with the claim's id. A claim that was there already
    # first looks for an open draft with that tag (made by an attempt that stopped before the claim took it) and
    # reuses it. Then the claim takes the draft (#take_draft) or the draft is removed again (two first views racing:
    # see #claim_checkout).
    def draft_claimed_checkout(claim, retried)
      adapter = Payments::ShopifyAdapter.new
      reference = Payments::Reference.new(kind: shopify_draft_order_key_name, record_id: id, checkout_id: claim.id)
      draft = (adapter.find_open_checkout(reference: reference) if retried) ||
              adapter.create_checkout(lines: shopify_draft_order_line_items, reference: reference)
      discard_unused_draft(draft.id) unless with_lock { take_draft(claim, draft.id) }
    end

    # Under the row lock (the row read again): the claim takes the draft `gid` while it is open with no other draft
    # and the rental may still take one, and the rental stores the same id. Any id it stored before has a checkout
    # record (#claim_checkout), so nothing is lost. A rental that moved on voids the claim. True when taken (or the
    # claim already has this draft).
    def take_draft(claim, gid)
      claimed = payment_checkouts.open.where(id: claim.id)
      unless may_take_draft_order?
        claimed.where(provider_id: nil).update_all(status: 'void', updated_at: Time.current)
        return false
      end

      taken = claimed.where('provider_id IS NULL OR provider_id = ?', gid).update_all(provider_id: gid, updated_at: Time.current) == 1
      store_shopify_draft_order_id(gid) if taken
      taken
    end

    def checkout_records_of(gid) = payment_checkouts.where(provider: PROVIDER, provider_id: gid)

    def checkout_term = owned_until&.to_date
  end
end
