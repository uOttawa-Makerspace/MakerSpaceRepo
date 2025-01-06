# frozen_string_literal: true

class LockerRental < ApplicationRecord
  include ApplicationHelper

  belongs_to :locker_type
  belongs_to :rented_by, class_name: "User"

  after_save :send_email_notification, if: :state_changed?

  enum state: {
         # Users submitted, not approved by admin
         reviewing: "reviewing",
         # Approved by admin, waiting for payment confirm
         await_payment: "await_payment",
         # Approved and paid, or assigned directly by admin
         active: "active",
         # Cancelled, no longer assigned
         cancelled: "cancelled"
       }

  # Locker type and state always present
  validates :locker_type, :state, presence: true
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

  scope :under_review, -> { where(state: %i[reviewing await_payment]) }
  scope :assigned, -> { where(state: :active) }

  # Used by the automated payment system, picks the first available
  # specifier and owned until end of this semester
  def auto_assign
    update(
      state: :active,
      owned_until: end_of_this_semester,
      locker_specifier: locker_type.get_available_lockers.first
    )
  end

  def full_locker_name
    "#{locker_type.short_form}##{locker_specifier}"
  end

  # FIXME rename to .pending?
  def under_review?
    reviewing? || await_payment?
  end

  def send_email_notification
    case state.to_sym
    when :await_payment
      LockerMailer.with(locker_rental: self).locker_checkout.deliver_now
    when :active
      LockerMailer.with(locker_rental: self).locker_assigned.deliver_now
    when :cancelled
      LockerMailer.with(locker_rental: self).locker_cancelled.deliver_now
    end
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
end
