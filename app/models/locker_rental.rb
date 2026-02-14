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
  belongs_to :rented_by, class_name: 'User'
  belongs_to :decided_by, class_name: 'User', optional: true
  belongs_to :course_name, optional: true

  before_validation :set_cancellation_date, if: :cancelled?
  
  after_save :send_email_notification
  after_save :sync_shopify_draft_order
  after_save :log_locker_rental_modification

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
            allow_nil: true, # Skip validation if nil, caught below anyways
            if: :reserves_locker?
  validates :locker, presence: true, if: :reserves_locker?

  # If set to active, make sure end date is there
  validates :owned_until, presence: true, if: :active?

  # If state ever changes from request, record who did it
  # Which staff member approved the request, or if owner cancelled the request
  validates :decided_by, presence: true, unless: :reviewing?

  # Track when rental was finished
  validates :cancelled_at, presence: true, if: :cancelled?

  # Locker rental always has an owner
  validates :rented_by, presence: true

  # If rented by a GNG student, make sure details are given
  validates :course_name, presence: true, if: :requested_as_student?
  validates :section_name, presence: true, if: :requested_as_student?
  # This is now group number, but I kept it this just in case
  validates :team_name, presence: true, if: :requested_as_student?

  # Scopes to aid sorting rentals
  scope :pending, -> { where(state: %i[reviewing await_payment]) }
  scope :reserves_locker, -> { where(state: %i[await_payment active]) }
  scope :assigned, -> { where(state: :active) }

  # Used by the automated payment system, picks the first available
  # specifier and owned until end of this semester
  def auto_assign
    update(
      {
        state: (:active unless active?),
        owned_until: (end_of_this_semester if owned_until.blank?),
        paid_at: Date.current
      }.compact
    )
  end

  def expired?
    active? && owned_until && owned_until <= DateTime.current
  end

  def expired_since
    # If there's a cancellation date, give that
    # else owned_until if it's expired
    cancelled_at || (owned_until if expired?)
  end

  # If expired for more than a week. Expired if owned_until or cancelled_at is
  # one week old
  def overdue?
    # safe navigation to call comparison operator
    expired? && expired_since < 1.week.ago
  end

  def overdue_for
    if overdue?
      
    end
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

  # Send emails when state changes
  def send_email_notification
    return unless saved_change_to_state?
    case state.to_sym
    when :await_payment
      LockerMailer.with(locker_rental: self).locker_checkout.deliver_later
    when :active
      LockerMailer.with(locker_rental: self).locker_assigned.deliver_later
    when :cancelled
      LockerMailer.with(locker_rental: self).locker_cancelled.deliver_later
    when :reviewing
      LockerMailer.with(locker_rental: self).locker_requested.deliver_later
    else
      raise "Unknown state #{state.to_sym}"
    end
  end

  def sync_shopify_draft_order
    return unless saved_change_to_state?
    case state.to_sym
    when :cancelled
      # When a locker is cancelled, cancel draft_order too
      destroy_shopify_draft_order
    end
  end

  def log_locker_rental_modification
    
  end
  
  # Fetch checkout link from shopify .Returns nil if API call fails or checkout
  # is not possible now.
  def checkout_link
    return nil unless await_payment? # checkout only if await payment

    shopify_draft_order['invoiceUrl']
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

  private

  # Definitions for the shopify concern

  def shopify_draft_order_line_items
    if Rails.env.production? || true
      [
        {
          quantity: 1,
          variantId: locker.locker_size.shopify_gid
        }
      ]
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
