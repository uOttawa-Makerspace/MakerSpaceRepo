# frozen_string_literal: true

class LockerRental < ApplicationRecord
  include ApplicationHelper
def start_shopify_session
      # shopify_api_key =
      #   Rails.application.credentials[Rails.env.to_sym][:shopify][:api_key]
      shopify_password =
        Rails.application.credentials[Rails.env.to_sym][:shopify][:password]
      shopify_shop_name =
        Rails.application.credentials[Rails.env.to_sym][:shopify][:shop_name]

      # ShopifyAPI::Base.api_version =
      #   Rails.application.credentials[Rails.env.to_sym][:shopify][:api_version]

      session = ShopifyAPI::Auth::Session.new(
        shop: "#{shopify_shop_name}.myshopify.com",
        access_token: shopify_password
      )

      # Activate session to be used in all API calls
      # session must be type `ShopifyAPI::Auth::Session`
      ShopifyAPI::Context.activate_session(session)

      session
    end

  belongs_to :locker_type
  belongs_to :rented_by, class_name: "User"

  after_save :send_email_notification

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

  # Fetch checkout link from shopify draft order, if not found create a draft
  # order. Returns nil if API call fails or checkout is not possible now.
  def checkout_link
    return nil unless await_payment?  # checkout only if await payment

    shopify_draft_order['data']['draftOrder']['invoiceUrl']
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

  # FIXME: wrap in a API cache block
  def shopify_draft_order
    if shopify_draft_order_id.blank?
      create_shopify_draft_order
    else
      fetch_shopify_draft_order
    end
  end

  def create_shopify_draft_order
    create_draft_order = <<~QUERY
      mutation draftOrderCreate($input: DraftOrderInput!) {
        draftOrderCreate(input: $input) {
          draftOrder {
            id
          }
          userErrors {
            field
            message
          }
        }
      }
    QUERY

    start_shopify_session
    admin_client = ShopifyAPI::Clients::Graphql::Admin.new(session: ShopifyAPI::Context.active_session)
    resp = admin_client.query(query: create_draft_order, variables: draft_order_input)

    # save ID in database
    update(shopify_draft_order_id: resp.body['data']['draftOrderCreate']['draftOrder']['id']) if resp.code == 200

    fetch_shopify_draft_order
  end

  def fetch_shopify_draft_order
        start_shopify_session
    admin_client = ShopifyAPI::Clients::Graphql::Admin.new(session: ShopifyAPI::Context.active_session)
    query_draft_order = <<~QUERY
    query {
      draftOrder(id: "#{shopify_draft_order_id}") {
        id
        name
        invoiceUrl
        status
        metafields(first: 10) {
          nodes {
            key
            value
            type
          }
        }
      }
    }
    QUERY

    admin_client.query(query: query_draft_order).body
    #raise 'huh'
  end

  def draft_order_input
    {"input" => locker_type.line_item.merge(draft_order_metafields)
    }
  end

  # metafields to track this rental ID inside the webhook handler
  def draft_order_metafields
    {
      "metafields": [
          {
            "namespace": "makerepo",
            "key": "locker_db_reference",
            "value": id.to_s, # attach this ID to the draft order
            "type": "string",
          }
        ],
    }
  end
end
