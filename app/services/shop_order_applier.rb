# frozen_string_literal: true

# Applies one stored Shopify order (a ProcessedOrder row) to the site: the locker payment, the membership paid and
# the CC Money credit of an orders/paid delivery, or the locker payment of an orders/fulfilled (cash) one.
#
# Everything is applied in ONE transaction together with the row's status change, with the lock waits bounded
# (own_transaction), after the row is locked FOR UPDATE: a second run of the same order finds it applied and does
# nothing, and any error rolls the whole application back, so a branch either applies or the order is retried (see
# ApplyProcessedOrderJob). Shopify is only asked (draft-order metafields) BEFORE the transaction, so no HTTP call
# holds a lock. Problems that are decisions rather than errors (the order names a membership or locker rental that
# does not exist, a CC order without an email, a refused metafield lookup) apply what can be applied and are
# reported for staff, after the commit, so a rolled-back attempt reports nothing. The CC claim mail is queued
# after the commit as well (Active Job here enqueues at once: enqueue_after_transaction_commit is false).
class ShopOrderApplier
  include ShopifyConcern

  # Raised only to be reported (Rails.error.report).
  class LockerOrderWithoutReference < StandardError; end
  class UnknownLockerRental < StandardError; end
  class UnknownMembership < StandardError; end
  class UnresolvedMembershipOrder < StandardError; end
  class UnresolvedCcOrder < StandardError; end
  # Shopify refused a metafield lookup for good (an access or invalid-id error): reported once, and the order goes
  # on without that reference. The locker and membership branches that needed it apply nothing (the reference is
  # unknown, not absent); the others apply as designed.
  class MetafieldLookupRejected < StandardError; end

  PROVIDER = "shopify"
  CC_PRODUCT_ID = 4_359_597_129_784
  LOCKER_KEY = "locker_db_reference"
  MEMBERSHIP_KEY = "membership_db_reference"
  PRODUCT_OF_KEY = { LOCKER_KEY => :locker, MEMBERSHIP_KEY => :membership }.freeze

  # What one stored payload asks for, classified once from the payload alone. The references and a refused lookup
  # are filled in by the Shopify lookup (resolve_references).
  Plan = Struct.new(:hook, :id, :topic, :locker, :membership, :email, :cc_items, :paid_at,
                    :locker_ref, :membership_ref, :lookup_rejection, :left_unapplied,
                    keyword_init: true) do
    alias_method :locker?, :locker
    alias_method :membership?, :membership

    # Something to apply. Plain merch and job-order orders have nothing and are not stored.
    def branches? = locker? || membership? || cc_items.any?
  end

  class << self
    # The Shopify order id: the payload's numeric "id", else the numeric tail of its admin_graphql_api_id
    # ("gid://shopify/Order/123"), so both spellings of one order are the same idempotency key.
    def order_id(hook)
      hook["id"].presence&.to_s || hook["admin_graphql_api_id"].presence&.to_s&.split("/")&.last
    end

    # Cheap, from the payload alone (no Shopify call, no database): what the order asks for.
    def plan_for(hook, topic: "orders/paid", received_at: nil)
      tags = hook["tags"]
      locker = LockerRental.draft_order_processable?(tags)
      if topic == "orders/fulfilled"
        # The cash was taken when the order was fulfilled, not when it was created (processed_at)
        fulfilled_at = Array(hook["fulfillments"]).filter_map { |f| parse_time(f["created_at"]) if f.is_a?(Hash) }.max
        return Plan.new(hook: hook, id: order_id(hook), topic: topic, locker: locker, membership: false, cc_items: [],
                        paid_at: fulfilled_at || received_at || Time.current)
      end

      Plan.new(
        hook: hook, id: order_id(hook), topic: topic, locker: locker,
        membership: Membership.draft_order_processable?(tags),
        email: hook.dig("customer", "email").presence,
        cc_items: Array.wrap(hook["line_items"]).select { |i| i.is_a?(Hash) && i["product_id"].to_i == CC_PRODUCT_ID }
      )
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end

  def initialize(record)
    @record = record
  end

  def call
    plan = self.class.plan_for(@record.payload, topic: @record.topic, received_at: @record.created_at)
    resolve_references(plan)

    ApplicationRecord.own_transaction("apply_processed_order") do
      order = ProcessedOrder.lock.find(@record.id)
      next unless order.status == "received"

      apply(plan)
      order.update!(status: "applied", applied_at: Time.current, last_error: nil, leased_until: nil)
      @applied_here = true
    end
  rescue StandardError => e
    raise unless post_commit_failure?

    # The order committed as applied and something that runs after the commit raised: not a failed attempt (the
    # order must not be applied again), so tell staff, who can resend whatever it was.
    report_after_commit_failure(e, "after_commit")
  end

  private

  def apply(plan)
    report_lookup_rejection(plan)
    apply_locker_order(plan) if plan.locker?
    apply_membership(plan) if plan.membership?
    apply_cc_money(plan) if plan.cc_items.any?
  end

  # ---- Shopify lookup (before the transaction)

  def draft_order_gid_from_hook(hook)
    if hook["draft_order_id"].present?
      "gid://shopify/DraftOrder/#{hook['draft_order_id']}"
    else
      hook["admin_graphql_api_id"]
    end
  end

  # The values of the makerepo metafields `keys` of an order: from the payload when it carries them, else from
  # ONE Shopify lookup of the draft order shared by all the keys. It can raise ShopifyContext::NotConfigured or
  # ShopifyConcern::MetafieldLookupFailed (the job retries). A lookup Shopify refuses for good yields no values
  # and is noted on the plan, so the order proceeds as "no reference".
  def resolve_references(plan)
    keys = []
    keys << LOCKER_KEY if plan.locker?
    keys << MEMBERSHIP_KEY if plan.membership? && plan.hook["line_items"].present?
    remote = :unfetched
    values = keys.index_with do |key|
      field = plan.hook["metafields"]&.find { |m| m["namespace"] == "makerepo" && m["key"] == key }
      if field.nil?
        remote = fetch_remote_metafields(plan) if remote == :unfetched
        field = remote&.find { |f| f["key"] == key }
        # the lookup that was meant to supply this reference was refused: the reference is unknown, not absent, so
        # the product is left unapplied (and reported with the refusal) instead of being treated as one without a reference
        (plan.left_unapplied ||= []) << PRODUCT_OF_KEY.fetch(key) if plan.lookup_rejection
      end
      field&.[]("value").presence
    end
    plan.locker_ref = values[LOCKER_KEY]
    plan.membership_ref = values[MEMBERSHIP_KEY]
  end

  def fetch_remote_metafields(plan)
    draft_order_metafields(draft_order_gid_from_hook(plan.hook))
  rescue ShopifyConcern::MetafieldLookupRejected => e
    plan.lookup_rejection = e.codes
    nil
  end

  # ---- reports

  # Reports a problem for staff to reconcile. Sent once the transaction has committed, so an attempt that rolls
  # back (and is retried) reports nothing and a retry does not report twice.
  def report_problem(error, context: {})
    after_commit("problem_report") { Rails.error.report(error, handled: true, severity: :error, context: context) }
  end

  # Runs a side effect once the transaction has committed. If it raises, the order is already applied, so the failure
  # is reported (order id and which side effect, no personal data) instead of failing the attempt.
  def after_commit(side_effect, &block)
    ActiveRecord.after_all_transactions_commit do
      block.call
    rescue StandardError => e
      report_after_commit_failure(e, side_effect)
    end
  end

  # The error is wrapped (class only): its message can carry values from the order.
  def report_after_commit_failure(error, side_effect)
    Rails.error.report(
      ApplyProcessedOrderJob::PostCommitSideEffectFailed.new(
        "order #{@record.provider_ref} was applied but its #{side_effect} failed (#{error.class})"
      ), handled: true, severity: :error,
         context: { shopify_order_id: @record.provider_ref, side_effect: side_effect, error_class: error.class.name }
    )
  end

  # True when this run committed the order as applied (so an error now came after the commit, not from the attempt).
  def post_commit_failure?
    @applied_here && ProcessedOrder.where(id: @record.id, status: "applied").exists?
  end

  # One report per cause, and the cause is the refusal: it names the products it left unapplied (the locker and
  # membership branches of an order whose reference it was meant to supply). Those branches send no report of
  # their own; orders that really carry no reference, with nothing refused, are still reported per product.
  def report_lookup_rejection(plan)
    return unless plan.lookup_rejection

    affected = Array(plan.left_unapplied)
    report_problem(
      MetafieldLookupRejected.new(
        "metafield lookup for order #{plan.id} rejected (#{plan.lookup_rejection.join(', ')}); " \
        "left unapplied: #{affected.join(', ').presence || 'nothing'}"
      ),
      context: { shopify_order_id: plan.id, codes: plan.lookup_rejection, affected: affected }
    )
  end

  # A membership or CC order whose target cannot be found, which no retry can fix: reported with the order id
  # and left to staff. The order is still applied.
  def report_unresolved(plan, error_class, branch, message, **extra_context)
    report_problem(error_class.new("#{branch} order #{plan.id} #{message}"),
                   context: { shopify_order_id: plan.id }.merge(extra_context))
  end

  # ---- locker

  def apply_locker_order(plan)
    return if plan.left_unapplied&.include?(:locker) # the refused lookup is reported once (report_lookup_rejection)

    # A locker-tagged order that names no locker rental at all: nothing to apply, and not to be lost silently
    # either (staff reconcile it from the report).
    if plan.locker_ref.blank?
      report_problem(LockerOrderWithoutReference.new("locker order #{plan.id} carries no locker_db_reference"),
                     context: { shopify_order_id: plan.id })
      return
    end

    rental = LockerRental.find_by(id: plan.locker_ref)
    unless rental
      report_problem(
        UnknownLockerRental.new("locker order #{plan.id} references unknown locker rental #{plan.locker_ref}"),
        context: { locker_rental_id: plan.locker_ref.to_s, shopify_order_id: plan.id }
      )
      return
    end

    # amount = the locker line only (nil when it cannot be told); order_total = the whole order. A malformed
    # or out-of-range figure is stored as nil and never fails the order; record_payment reports it (ids only)
    # after its commit, and only when the payment row is really new, so a replayed delivery does not report it again.
    hook = plan.hook
    problems = []
    rental.record_payment(
      shopify_order_id: plan.id,
      paid_at: plan.paid_at || self.class.parse_time(hook["processed_at"]) || @record.created_at,
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

  # ---- membership

  def apply_membership(plan)
    if plan.hook["line_items"].blank?
      report_unresolved(plan, UnresolvedMembershipOrder, "membership", "has no line items")
      return
    end

    # A membership order whose reference lookup was refused is not an order without a reference: the pending
    # membership it names is still unpaid, and matching by email or title would create a second, paid one.
    # Nothing is applied for membership; the refusal is reported once (report_lookup_rejection).
    return if plan.left_unapplied&.include?(:membership)

    if plan.membership_ref.present?
      membership = Membership.find_by(id: plan.membership_ref)
      if membership
        membership.update!(status: :paid)
      else
        report_unresolved(plan, UnknownMembership, "membership", "references unknown membership #{plan.membership_ref}")
      end
      return
    end

    apply_membership_by_email(plan)
  end

  # Fallback when the order carries no membership reference: the customer's email names the user (users.email is
  # case-insensitive) and each line item's title the tier (checkout sells one membership per line, quantity 1).
  # Each matched tier line is a new membership with the current dates.
  def apply_membership_by_email(plan)
    if plan.email.blank?
      report_unresolved(plan, UnresolvedMembershipOrder, "membership", "has no membership reference and no customer email")
      return
    end

    user = User.find_by(email: plan.email)
    unless user
      report_unresolved(plan, UnresolvedMembershipOrder, "membership", "has no membership reference and its customer is not a user")
      return
    end

    created = 0
    Array.wrap(plan.hook["line_items"]).each do |item|
      title = item.is_a?(Hash) ? item["title"].to_s.strip : ""
      tier = MembershipTier.where("LOWER(title_en) = ? OR LOWER(title_fr) = ?", title.downcase, title.downcase).first
      next unless tier

      Membership.create!(user: user, membership_tier: tier, status: :paid)
      created += 1
    end
    return if created.positive?

    report_unresolved(plan, UnresolvedMembershipOrder, "membership", "has no membership reference and no line item names a tier")
  end

  # ---- CC Money

  # One CC row per CC product line item.
  def apply_cc_money(plan)
    if plan.email.blank?
      report_unresolved(plan, UnresolvedCcOrder, "CC", "has the CC product but no customer email")
      return
    end

    user = User.find_by(email: plan.email)
    plan.cc_items.each do |item|
      cc = 10 * item["quantity"].to_i
      if user.present?
        CcMoney.create!(user_id: user.id, cc: cc)
      else
        new_cc = CcMoney.create!(cc: cc, linked: false)
        hash = Rails.application.message_verifier(:cc).generate(new_cc.id)
        email = plan.email
        after_commit("cc_claim_mail") { MsrMailer.send_cc_money_email(email, cc, hash).deliver_later }
      end
    end
  end
end
