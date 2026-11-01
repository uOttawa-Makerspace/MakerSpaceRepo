# frozen_string_literal: true

# Describes a locker ownership lifecycle. Goes from under review to active, or
# under review to payment to active. Can be cancelled by admins at any time. Can
# be cancelled by users if still under review
class LockerRental < ApplicationRecord
  include ApplicationHelper
  # Fetch checkout url via shopify
  include ShopifyConcern

  # Associated when assigned
  belongs_to :locker, optional: true
  belongs_to :preferred_locker, class_name: 'Locker', optional: true
  # Unscoped from User's default scope (deleted = false) so a soft-deleted renter still loads: staff can
  # still cancel such a rental and see who it belonged to. Whether a renter may HOLD a locker is the
  # explicit renter_eligible? rule below, never an accident of the association returning nil.
  belongs_to :rented_by, -> { unscope(where: :deleted) }, class_name: 'User'
  # Never deleted with the rental: a payment is a financial record.
  has_many :locker_payments
  belongs_to :decided_by, class_name: 'User', optional: true
  belongs_to :course_name, optional: true

  before_validation :set_cancellation_date, if: :cancelled?

  # Nor is the Shopify draft order synced from a callback (an HTTP call inside the caller's transaction, holding
  # the rental row lock): the cancelling path calls #sync_shopify_draft_order_after_commit after the commit.
  # The state-change and move mails are NOT sent from a callback: a callback runs inside the caller's
  # transaction (the Shopify webhook's, the staff update's), and Active Job here enqueues immediately
  # (enqueue_after_transaction_commit is false), so a rollback would still send the mail. The code paths
  # that change state call #notify_after_commit explicitly, which delivers after the outermost commit.

  # Virtual attribute to handle the 'Indefinite' checkbox from the forms
  attr_accessor :indefinite

  enum :state,
       {
         # Users submitted, not approved by admin
         reviewing: 'reviewing',
         # Approved by admin, waiting for payment confirm
         await_payment: 'await_payment',
         # Approved and paid, or assigned directly by admin
         active: 'active',
         # Cancelled, no longer assigned
         cancelled: 'cancelled'
       },
       validate: true,
       default: :reviewing

  # Shares the enum with the other class,
  # not really work making a whole concern for one enum
  enum :requested_as,
       { staff: 'staff', student: 'student', general: 'general' },
       prefix: true

  # specifier is a string, call #squish on it
  normalizes :specifier, with: :squish

  # When submitting a request, ensure only one is present
  validate :only_one_request_per_user, on: :create
  def only_one_request_per_user
    # If this request is under review, and another by same user is also under review
    if pending? &&
         LockerRental.where(rented_by: rented_by).exists?(
           state: %i[reviewing await_payment]
         )
      errors.add(:rented_by, 'already has a request under review')
    end
  end

  # If rental was approved and sent to checkout or assignment, don't double
  # assign lockers of same locker type if assigned
  validates :locker,
            uniqueness: {
              conditions: -> { reserves_locker }
            },
            allow_nil: true,
            if: :reserves_locker?
  validates :locker, presence: true, if: :reserves_locker?

  # Active rentals require an owned_until date unless explicitly marked as indefinite.
  # This restores safety while allowing the virtual attribute to bypass it when necessary.
  validates :owned_until, presence: true, if: -> { active? && indefinite != '1' }

  # If state ever changes from request, record who did it
  # Which staff member approved the request, or if owner cancelled the request
  validates :decided_by, presence: true, unless: :reviewing?

  # Track when rental was finished
  validates :cancelled_at, presence: true, if: :cancelled?

  # Locker rental always has an owner
  validates :rented_by, presence: true

  # Only an eligible renter (row exists, not soft-deleted, not deactivated) can be given a locker: not when
  # the rental is created, not when it is reassigned (rented_by_id changes), and not when an existing one
  # (e.g. a reviewing request of a user deactivated since) is activated or sent to payment. Other changes
  # (cancelling, ending, notes) stay possible so staff can clean up.
  validate :rented_by_eligible, if: -> {
    new_record? || rented_by_id_changed? || (state_changed? && (active? || await_payment?))
  }
  def rented_by_eligible
    return if rented_by.nil? # the presence validation reports a missing renter
    return if renter_eligible?

    errors.add(:rented_by, rented_by.deleted? ? :deleted : :deactivated)
  end

  # The one eligibility rule. The renter row is read FOR SHARE: it conflicts with the FOR NO KEY UPDATE
  # that User#deactivate! (and soft delete) take, so a deactivation either commits first (and this sees
  # it) or waits for this transaction (the validations run inside save's transaction, and the webhook's),
  # instead of interleaving. (The foreign-key check takes only FOR KEY SHARE, which does not conflict.)
  # pick, not exists?, so the lock clause is certainly emitted.
  # lock: false is for read-only callers outside a transaction (mail, the expiry task): same rule, no row lock.
  def renter_eligible?(lock: true)
    # A renter not saved yet (a built record) has no row to read or lock; judge its attributes.
    return !rented_by.deleted? && rented_by.deactivated_at.nil? if rented_by_id.blank? && rented_by&.new_record?
    return false if rented_by_id.blank?

    renters = User.eligible_renters.where(id: rented_by_id)
    renters = renters.lock('FOR SHARE') if lock
    renters.pick(:id).present?
  end

  # If rented by a GNG student, make sure details are given
  validates :course_name, presence: true, if: :requested_as_student?
  validates :section_name, presence: true, if: :requested_as_student?
  # This is now group number, but I kept it this just in case
  validates :team_name, presence: true, if: :requested_as_student?

  # Scopes to aid sorting rentals
  scope :pending, -> { where(state: %i[reviewing await_payment]) }
  scope :reserves_locker, -> { where(state: %i[await_payment active]) }
  scope :assigned, -> { where(state: :active) }
  
  # Added this missing scope so the admin controller can exclude cancelled rentals
  scope :not_cancelled, -> { where.not(state: :cancelled) }

  # Rentals with at least one payment staff still have to decide on (LockerPayment status held). The single
  # rule behind the staff list section, the badge in the tables and the alert on the rental page.
  scope :with_held_payment, lambda {
    where(LockerPayment.held.where('locker_payments.locker_rental_id = locker_rentals.id').arel.exists)
  }

  # Records one Shopify order that paid this rental, in one transaction, and applies it when it can be.
  # Idempotent on the order id (INSERT ... ON CONFLICT DO NOTHING): a retry returns nil and changes, mails
  # and reports nothing. Returns the LockerPayment (applied or held), or nil for a duplicate.
  #   applied: the rental becomes active if it is not (owned_until defaulted, activation mail)
  #   held (reason recorded, rental untouched, reported once): rental cancelled, renter not eligible
  #     (deactivated / soft-deleted / missing), the rental cannot be activated (not_activatable), or it is
  #     already active and paid (already_paid: a duplicate)
  # `malformed_amounts`: names of the figures the caller could not read (it stored nil for them); reported once,
  # after the commit, only for a new payment row (a replay reports nothing), like a held payment.
  # Serialised per rental by the row lock, so two simultaneous deliveries cannot both apply.
  def record_payment(shopify_order_id:, paid_at: Time.current, amount: nil, currency: nil, order_total: nil, malformed_amounts: [])
    payment = nil
    transaction do
      lock!
      status, reason =
        if cancelled? then ['held', 'rental_cancelled']
        elsif !renter_eligible? then ['held', 'renter_ineligible']
        # already active and already paid for: this one is a duplicate charge (a renewal goes through await_payment)
        elsif already_paid? then ['held', 'already_paid']
        else ['applied', nil]
        end
      inserted = LockerPayment.insert(
        { locker_rental_id: id, shopify_order_id: shopify_order_id.to_s, paid_at: paid_at, amount: amount,
          currency: currency, order_total: order_total, status: status, hold_reason: reason,
          resolved_at: (Time.current if status == 'applied') },
        unique_by: :shopify_order_id, returning: %w[id]
      )
      if inserted.rows.any?
        payment = LockerPayment.find(inserted.rows.first.first)
        if status == 'applied' && !active?
          payment = activate_for_payment(payment)
          notify_after_commit if payment.applied?
        end
        # Display-only "latest payment", moved only by an APPLIED payment: a held one (cancelled rental,
        # ineligible renter) must not show the renter "Paid on".
        stamp_paid_at(paid_at) if payment.applied?
        report_held_payment(payment) if payment.held?
        report_malformed_amounts(payment, malformed_amounts)
      end
    end
    payment
  end

  # Hold reasons that assigning (or reactivating) can cure; a payment held because the rental was cancelled is
  # only ever refunded or dismissed.
  SETTLEABLE_HOLD_REASONS = %w[renter_ineligible not_activatable].freeze

  # Already paid for: an active rental with a paid_at. paid_at is only ever written for an applied payment (or
  # predates payment rows: legacy rentals), so it alone tells; a held payment never switches this off. A renewal
  # passes through await_payment, where it is not active, so its payment is applied.
  def already_paid?
    active? && paid_at.present?
  end

  # Staff assigned this rental active: ONE of its held payments (the oldest that this can cure) is now the
  # applied payment. Any other held payment stays held on purpose: a second charge for the same rental is a
  # duplicate, and must stay visible so staff refund it. Call inside the transaction of the assigning save.
  # Returns the number of payments applied (0 or 1).
  def settle_held_payments!(by: nil)
    # Oldest first; one lost to a concurrent refund/dismiss (mark_applied! is a conditional UPDATE) is skipped
    # and the next curable one is tried. At most one is ever applied.
    locker_payments.held.where(hold_reason: SETTLEABLE_HOLD_REASONS).order(:paid_at, :id).each do |payment|
      return 1 if payment.mark_applied!(by: by)
    end
    0
  end

  # The amount of this rental's own LOCKER line in a paid order's line_items (price x quantity - discount), or
  # nil when it cannot be told reliably (no line matches). Never the order total, which may include a
  # membership or CC money. The line is recognised the way the draft order was built (see
  # #shopify_draft_order_line_items): in production by its variant, elsewhere by its title.
  # The discount is the sum of the line's discount_allocations[].amount (what Shopify's orders/paid carries,
  # order-level discounts included); only when that array is absent does the legacy total_discount apply, so the
  # same discount is never counted twice.
  # Raises ArgumentError for a malformed amount (the webhook stores nil and reports it).
  def locker_line_amount(line_items)
    return nil unless line_items.is_a?(Array)

    matcher = locker_line_matcher
    return nil unless matcher

    lines = line_items.select { |line| line.is_a?(Hash) && matcher.call(line) }
    return nil if lines.empty?

    total = lines.sum do |line|
      quantity = line['quantity'].presence ? Integer(line['quantity'].to_s) : 1
      (LockerPayment.money(line['price']) || 0) * quantity - line_discount(line)
    end
    LockerPayment.money(total)
  rescue TypeError
    raise ArgumentError, 'malformed line item'
  end

  # Expired if a locker is active (not cancelled or unpaid) and time has passed owned_until
  def expired?
    # Only expired if active, has an owned_until date, and it has passed
    active? && owned_until && owned_until <= DateTime.current
  end

  def renewable?
    active? && expired?
  end

  # How long was this expired for
  def expired_since
    # If there's a cancellation date, give that
    # else owned_until if it's expired
    cancelled_at || (owned_until if expired?)
  end

  # If expired for more than a week. Expired if owned_until or cancelled_at is
  # one week old
  def overdue?
    expired? && expired_since && expired_since < 1.week.ago
  end

  # Is a rental not confirmed yet? Usually means users can cancel rental
  def pending?
    reviewing? || await_payment?
  end

  # Does rental have a locker reserved? Payment pending and active rentals
  # reserve a locker and prevent double-assignment
  def reserves_locker?
    await_payment? || active?
  end

  def set_cancellation_date
    self.cancelled_at = DateTime.now
  end

  # Mails for the LAST save of this record (a state change, or a move of an active rental), delivered after
  # the outermost transaction commits, or at once when none is open; dropped if it rolls back. Call it right
  # after the save that changed the state, from the code path that made the change (the webhook payment,
  # the staff create/update, renew). Nothing is sent by saving alone.
  def notify_after_commit
    mails = notification_mails
    return if mails.empty?

    ActiveRecord.after_all_transactions_commit { mails.each(&:deliver_later) }
  end

  # Per transition (unchanged from when this was an after_save): the mail for the new state, or the
  # moved mail for a locker/date change of an already active rental. Built (not sent) from the
  # saved changes, so they are captured before another save overwrites them.
  def notification_mails
    mailer = LockerMailer.with(locker_rental: self)
    if saved_change_to_state?
      case state.to_sym
      when :await_payment then [mailer.locker_checkout]
      when :active then [mailer.locker_assigned]
      when :cancelled then [mailer.locker_cancelled]
      when :reviewing then [mailer.locker_requested]
      else raise "Unknown state #{state.to_sym}"
      end
    elsif active? && (saved_change_to_locker_id? || saved_change_to_owned_until?)
      [
        LockerMailer.with(
          locker_rental: self,
          moved_locker: Locker.find_by(id: saved_change_to_locker_id&.first),
          moved_date: saved_change_to_owned_until
        ).locker_moved
      ]
    else
      []
    end
  end

  # EVERY code path that cancels a rental must call this after its transaction has committed, or a cancelled
  # rental keeps a payable Shopify invoice (a late payment would then only be caught as a held payment).
  # Current callers: LockerRentalsController#update (the only place a rental is cancelled: staff end/cancel and
  # the renter cancelling a pending request).
  #
  # After a save that cancelled this rental, takes its Shopify draft order away by the one shared rule
  # (ShopifyConcern::DraftRemoval, the same classification JobOrder uses). Call it AFTER the transaction has
  # committed (no row lock is held during the HTTP call). The cancellation is already committed, so a Shopify
  # failure cannot undo it. What the stored id becomes follows the outcome, as for a job order:
  #   deleted / gone  the id is forgotten (nothing left to remove)
  #   completed       the draft is PAID (it became an order, the payment record): nothing to remove, the id is kept,
  #                   no report, no alert (ending a paid rental is not a failure)
  #   still open      a payable invoice that could not be deleted: reported, id kept, false returned; a payment that
  #                   still arrives is recorded as held (rental_cancelled) for staff to refund
  # An exception (HTTP, timeout, configuration, no answer) is the same failure. Returns true when there was nothing
  # to do or nothing is left to remove.
  class DraftOrderNotDeleted < StandardError; end

  def sync_shopify_draft_order_after_commit
    return true unless saved_change_to_state? && cancelled?

    gid = shopify_draft_order_id
    return true if gid.blank?

    result = ShopifyConcern::DraftRemoval.call(gid)
    case result.outcome
    when :deleted, :gone then forget_draft_order_id(gid)
    when :completed then nil
    else
      raise DraftOrderNotDeleted,
            "Shopify did not delete the open draft order #{gid}: #{result.user_errors.map { |e| e['message'] }.join(', ')}"
    end
    true
  rescue StandardError => e
    Rails.error.report(e, handled: true, severity: :error, context: { locker_rental_id: id, step: 'delete_shopify_draft_order' })
    false
  end

  # Fetch checkout link from shopify. Returns nil if API call fails or checkout is not possible now.
  # A stored draft is just fetched. When there is none it is created on Shopify first, outside any lock (no HTTP
  # call runs under the row lock), then stored only if, under the row lock, the rental is still awaiting payment
  # and still has no draft: a cancel that committed meanwhile (its after-commit sync saw no id, so would never
  # delete this draft) would otherwise leave a payable draft on a cancelled rental. A draft that is not kept is
  # removed again, after the lock is released.
  def checkout_link
    return nil unless await_payment?
    return shopify_draft_order['invoiceUrl'] if shopify_draft_order_id.present?

    create_checkout_draft
  end

  # For the view
  def state_icon
    LockerRental.state_icon(state)
  end

  def self.state_icon(state)
    case state
    when 'active'
      'fa-lock'
    when 'cancelled'
      'fa-clock-o text-danger'
    else
      ''
    end
  end

  def self.get_assigned_lockers
    LockerRental
      .where(state: :active)
      .pluck(:locker_type_id, :locker_specifier)
      .group_by(&:shift)
      .transform_values(&:flatten)
  end

  # Display-only "latest applied payment" (GREATEST), written only when a payment becomes applied.
  # One UPDATE with GREATEST in SQL (never the in-memory value, which may be stale).
  def stamp_paid_at(time)
    sql = self.class.sanitize_sql_array(
      ['UPDATE locker_rentals SET paid_at = GREATEST(paid_at, ?) WHERE id = ? RETURNING paid_at', time, id]
    )
    # exec_query, not select_value: a write, so it clears the query cache (a cached read of this rental in the
    # same request must see the new paid_at)
    row = self.class.connection.exec_query(sql).first
    @attributes.write_from_database('paid_at', row && row['paid_at'])
  end

  private

  def create_checkout_draft
    ensure_can_use_draft_order
    new_id, _line_items = create_remote_draft_order # Shopify, no lock

    kept = false
    transaction do
      lock! # reloads: the state and the draft id are read now
      if await_payment? && shopify_draft_order_id.blank?
        update_column(:shopify_draft_order_id, new_id)
        kept = true
      end
    end
    return fetch_shopify_draft_order&.dig('invoiceUrl') if kept

    discard_unused_draft(new_id)
    # Another request stored its draft first: that one is the invoice.
    await_payment? && shopify_draft_order_id.present? ? fetch_shopify_draft_order&.dig('invoiceUrl') : nil
  end

  # The draft created for a checkout that lost the race. The lock is released; the shared rule decides what the
  # outcome means, and only a draft that is still open and could not be deleted is a failure.
  def discard_unused_draft(gid)
    result = ShopifyConcern::DraftRemoval.call(gid)
    return unless result.outcome == :open

    raise DraftOrderNotDeleted, "Shopify did not delete the unused draft order #{gid}: #{result.user_errors.map { |e| e['message'] }.join(', ')}"
  rescue StandardError => e
    Rails.error.report(e, handled: true, severity: :error, context: { locker_rental_id: id, step: 'delete_unused_shopify_draft_order' })
  end

  # Forgets the stored draft id, only if it is still `gid` (a conditional UPDATE, never over a newer draft).
  def forget_draft_order_id(gid)
    self.class.where(id: id, shopify_draft_order_id: gid).update_all(shopify_draft_order_id: nil)
    @attributes.write_from_database('shopify_draft_order_id', nil) if shopify_draft_order_id == gid
  end

  # A callable telling whether a payload line item is this rental's locker line, built once from the expected
  # variant (production) or title (elsewhere); nil when the rental has no locker (no draft can exist).
  def locker_line_matcher
    built = locker ? shopify_draft_order_line_items.first : nil
    return nil unless built

    if built[:variantId]
      variant = built[:variantId].to_s.split('/').last
      ->(line) { line['variant_id'].to_s == variant }
    else
      title = built[:title]
      ->(line) { line['title'].to_s == title }
    end
  end

  def line_discount(line)
    allocations = line['discount_allocations']
    if allocations.is_a?(Array)
      allocations.sum do |allocation|
        # An entry that is not a Hash, or has no amount, is malformed: the whole locker amount becomes nil
        raise ArgumentError, 'malformed discount allocation' unless allocation.is_a?(Hash) && allocation['amount'].present?

        LockerPayment.money(allocation['amount'])
      end
    else
      LockerPayment.money(line['total_discount']) || 0
    end
  end

  # Activates the rental for an applied payment inside a savepoint. A rental that cannot be made valid
  # (reviewing with no locker, ...) must not fail the webhook (Shopify would retry forever): the payment
  # is held as not_activatable and staff decide.
  def activate_for_payment(payment)
    transaction(requires_new: true) do
      update!(state: :active, owned_until: owned_until.presence || end_of_this_semester)
    end
    payment
  rescue ActiveRecord::RecordInvalid
    reload
    payment.update!(status: 'held', hold_reason: 'not_activatable', resolved_at: nil)
    payment
  end

  # One report per malformed figure of a NEW payment, after the outermost commit, ids only.
  def report_malformed_amounts(payment, whats)
    whats = Array(whats).dup
    return if whats.empty?

    ActiveRecord.after_all_transactions_commit do
      whats.each do |what|
        Rails.error.report(
          LockerPayment::MalformedPaymentAmount.new(
            "paid locker order #{payment.shopify_order_id}: #{what} is malformed or out of range; stored as nil (rental #{id})"
          ),
          handled: true, severity: :error, context: { locker_rental_id: id, shopify_order_id: payment.shopify_order_id }
        )
      end
    end
  end

  # One report per held payment, after the outermost commit, ids only (no email, no name).
  def report_held_payment(payment)
    ActiveRecord.after_all_transactions_commit do
      Rails.error.report(
        LockerPayment::Held.new(
          "locker payment #{payment.id} (rental #{id}, user #{rented_by_id}) is held: #{payment.hold_reason}"
        ),
        handled: true, severity: :error,
        context: { locker_payment_id: payment.id, locker_rental_id: id, user_id: rented_by_id, hold_reason: payment.hold_reason }
      )
    end
  end

  # Definitions for the shopify concern

  def shopify_draft_order_line_items
    if Rails.env.production?
      [{ quantity: 1, variantId: locker.locker_size.shopify_gid }]
    else
      # Make a free locker, yay
      [
        {
          quantity: 1,
          title: "TEST locker on #{Rails.env} environment.",
          originalUnitPriceWithCurrency: {
            amount: '0',
            currencyCode: 'CAD'
          }
        }
      ]
    end
  end

  # name of the metafield key stored on shopify side
  # This is constant per model, do not change at all please.
  def self.shopify_draft_order_key_name
    'locker'
  end
end
