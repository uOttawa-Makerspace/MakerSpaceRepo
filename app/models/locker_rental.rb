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
  belongs_to :rented_by, class_name: "User"
  belongs_to :decided_by, class_name: "User", optional: true
  # optional because some students don't always have a repository ready beforehand
  belongs_to :repository, optional: true

  after_save :send_email_notification
  after_save :sync_shopify_draft_order

  enum :state,
       {
         # Users submitted, not approved by admin
         reviewing: "reviewing",
         # Approved by admin, waiting for payment confirm
         await_payment: "await_payment",
         # Approved and paid, or assigned directly by admin
         active: "active",
         # Cancelled, no longer assigned
         cancelled: "cancelled"
       },
       validate: true,
       default: :reviewing

  # Shares the enum with the other class,
  # not really work making a whole concern for one enum
  enum :requested_as,
       { staff: "staff", student: "student", general: "general" },
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
      errors.add(:rented_by, "already has a request under review")
    end
  end

  # If set to active
  with_options if: :active? do |rental|
    # Don't double assign lockers of same locker type if assigned
    rental.validates :locker,
                     uniqueness: {
                       conditions: -> { assigned }
                     },
                     allow_nil: true # Skip validation if nil, caught below anyways
    rental.validates :locker, :owned_until, presence: true
  end

  # If state ever changes from request, record who did it
  # Which staff member approved the request, or if owner cancelled the request
  validates :decided_by, presence: true, unless: :reviewing?

  # Locker rental always has an owner
  validates :rented_by, presence: true

  # Scopes to aid sorting rentals
  scope :pending, -> { where(state: %i[reviewing await_payment]) }
  scope :assigned, -> { where(state: :active) }

  def auto_assign_parameters
    {
      state: (:active unless active?),
      owned_until: (end_of_this_semester if owned_until.blank?),
      paid_at: Date.current
    }.compact
  end

  # Used by the automated payment system, picks the first available
  # specifier and owned until end of this semester
  def auto_assign
    update(
      auto_assign_parameters
      # state: :active,
      # owned_until: end_of_this_semester,
      # locker_specifier: locker_type.get_available_lockers.first
    )
  end

  def pending?
    reviewing? || await_payment?
  end

  # Send emails when state changes
  def send_email_notification
    return unless saved_change_to_state?
    case state.to_sym
    when :await_payment
      LockerMailer.with(locker_rental: self).locker_checkout.deliver_now
    when :active
      LockerMailer.with(locker_rental: self).locker_assigned.deliver_now
    when :cancelled
      LockerMailer.with(locker_rental: self).locker_cancelled.deliver_now
    when :reviewing
      nil # do nothing
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

  # Fetch checkout link from shopify .Returns nil if API call fails or checkout
  # is not possible now.
  def checkout_link
    return nil unless await_payment? # checkout only if await payment

    shopify_draft_order["invoiceUrl"]
  end

  # For the view
  def state_icon
    LockerRental.state_icon(state)
  end

  def self.state_icon(state)
    case state
    when "active"
      "fa-lock"
    when "cancelled"
      "fa-clock-o text-danger"
    else
      ""
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
    if Rails.env.production?
      [
        {
          quantity: 1,
          # FIXME: Locker product ID is hardcoded here
          # locker product ID 10478024917048
          # variant ID is 50851781312568
          variantId: "gid://shopify/ProductVariant/50851781312568"
        }
      ]
    else
      # Make a free locker, yay
      [
        {
          quantity: 1,
          title:
            "TEST locker on #{Rails.env} environment.",
          originalUnitPriceWithCurrency: {
            amount: "0",
            currencyCode: "CAD"
          }
        }
      ]
    end
  end

  # name of the metafield key stored on shopify side
  # This is constant per model, do not change at all please.
  def shopify_draft_order_key_name
    "locker"
  end
end
