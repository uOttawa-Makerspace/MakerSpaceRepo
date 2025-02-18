# frozen_string_literal: true

class LockerRental < ApplicationRecord
  include ApplicationHelper
  include ShopifyConcern

  belongs_to :locker_type
  belongs_to :rented_by, class_name: "User"
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
       }, validate: true

  # Shares the enum with the other class,
  # not really work making a whole concern for one enum
  enum :requested_as, LockerType.available_fors, prefix: true

  # Locker type and state and request_as always present
  validates :locker_type, :state, :requested_as, presence: true
  # When submitting a request, ensure only one is present
  validate :only_one_request_per_user, on: :create
  def only_one_request_per_user
    # If this request is under review, and another by same user is also under review
    if under_review? &&
       LockerRental.where(rented_by: rented_by).exists?(
         state: %i[reviewing await_payment]
       )
      errors.add(:rented_by, "already has a request under review")
    end
  end

  # Make sure the locker type requested has quantity available on request
  validate :locker_type_requested_is_available, on: :create
  def locker_type_requested_is_available
    return if locker_type.quantity_available.positive?
    errors.add(:locker_type, "No lockers of this type are available for request")
  end

  # If set to active
  with_options if: :active? do |rental|
    # Don't double assign lockers of same locker type if assigned
    # TODO upgrade Rails and add normalization to trim spaces
    # or change column type to integer not string
    validates :locker_specifier,
              uniqueness: {
                scope: :locker_type,
                conditions: -> { assigned }
              },
              allow_nil: true # Skip validation if nil, caught below anyways
    rental.validates :rented_by, :owned_until, :locker_specifier, presence: true
  end

  # Scopes to aid sorting rentals
  scope :under_review, -> { where(state: %i[reviewing await_payment]) }
  scope :assigned, -> { where(state: :active) }

  def auto_assign_parameters
    {
      state: (:active unless active?),
      owned_until: (end_of_this_semester if owned_until.blank?),
      locker_specifier:
        (locker_type.get_available_lockers.first if locker_specifier.blank?)
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

  def full_locker_name
    "#{locker_type.short_form}##{locker_specifier}"
  end

  # FIXME: rename to .pending?
  def under_review?
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
      # When a locker is cancelled, cancel draft order too
      destroy_shopify_draft_order
    end
  end

  # Fetch checkout link from shopify draft order, if not found create a draft
  # order. Returns nil if API call fails or checkout is not possible now.
  def checkout_link
    return nil unless await_payment?  # checkout only if await payment

    shopify_draft_order['invoiceUrl']
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
  # Definitions for the shopify concern:

  def shopify_draft_order_line_items
    [
      {
        "quantity": 1,
        "title": "Locker Rental for one semester / Location de casier pour un trimestre",
        "originalUnitPriceWithCurrency": {
          "amount": locker_type.cost,
          "currencyCode": "CAD",
        },
      }
    ]
  end

  # name of the metafield key stored on shopify side
  # This is constant per model, do not change at all please.
  def shopify_draft_order_key_name
    "locker"
  end
end
