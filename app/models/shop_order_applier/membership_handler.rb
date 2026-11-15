# frozen_string_literal: true

class ShopOrderApplier
  # The membership an order pays: the pending membership its metafield names, else (an order with no reference) new
  # paid memberships for the customer, one per line item that names a tier.
  class MembershipHandler < Handler
    def self.metafield_key(hook) = ("membership_db_reference" if hook["line_items"].present?)

    def call
      return unresolved("has no line items") if hook["line_items"].blank?

      # A membership order whose reference lookup was refused is not an order without a reference: the pending
      # membership it names is still unpaid, and matching by email or title would create a second, paid one.
      # Nothing is applied for membership; the refusal is reported once (report_lookup_rejection).
      return if left_unapplied?

      reference.present? ? apply_referenced : apply_by_email
    end

    private

    def unresolved(message, error_class = UnresolvedMembershipOrder, **context)
      applier.report_unresolved(plan, error_class, "membership", message, **context)
    end

    # Only a pending membership becomes paid. One that is already paid, revoked, failed or expired is left as it is and
    # reported with the order, so a late or second order cannot reactivate a membership staff took away.
    def apply_referenced
      ref = reference
      membership = Membership.find_by(id: ref)
      if membership.nil?
        applier.refuse("membership reference #{ref} not found")
        unresolved("references unknown membership #{ref}", UnknownMembership)
      elsif !membership.mark_paid_if_pending
        refuse(membership)
      end
    end

    # Records the refusal on the order (see ProcessedOrder.refused) and reports it.
    def refuse(membership)
      detail = "membership #{membership.id} is #{membership.reload.status}, not pending"
      applier.refuse(detail)
      unresolved("references #{detail}", MembershipNotPending, membership_id: membership.id)
    end

    # Fallback when the order carries no membership reference: the customer's email names the user and each line item's title the tier (checkout sells one membership per line, quantity 1).
    # Each matched tier line is a new paid membership starting when the member's latest active one ends (or now).
    def apply_by_email
      return unresolved("has no membership reference and no customer email") if email.blank?

      return unresolved("has no membership reference and its customer is not a user") unless customer
      return if grant_tiers(customer).positive?

      unresolved("has no membership reference and no line item names a tier")
    end

    # Grants one membership per line item whose title names a tier; returns how many.
    def grant_tiers(user)
      tiers = Array.wrap(hook["line_items"]).filter_map { |item| tier_named(item) }
      tiers.each { |tier| Membership.grant!(user, tier) }
      tiers.size
    end

    def tier_named(item)
      title = item.is_a?(Hash) ? item["title"].to_s.strip.downcase : ""
      MembershipTier.where("LOWER(title_en) = ? OR LOWER(title_fr) = ?", title, title).first
    end
  end
end
