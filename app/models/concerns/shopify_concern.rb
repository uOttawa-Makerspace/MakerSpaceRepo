# frozen_string_literal: true

module ShopifyConcern
  extend ActiveSupport::Concern

  # The gid-level Shopify calls (a draft order id, no record). Deliberately not class methods of the models that
  # include the concern: they skip #ensure_can_use_draft_order, so lockers and memberships must not gain them.
  # Used by the concern's instance methods and by JobOrder (its draft rule, JobOrder::DraftSweep).
  module DraftOrders
    # THE Admin GraphQL client builder (ShopifyService.admin_client uses it too): starts the session and builds the client.
    def self.client
      ShopifyContext.start_session!
      ShopifyAPI::Clients::Graphql::Admin.new(session: ShopifyAPI::Context.active_session)
    end

    # One getDraftOrder query that tells three outcomes apart: [:found, draft], [:gone, nil] (HTTP 200 with
    # `draftOrder: null` and no GraphQL errors) and [:error, nil] (non-200 or an error payload). Exceptions
    # propagate (unknown, never "gone").
    def self.fetch_result(gid)
      query_draft_order = <<~QUERY
        query getDraftOrder($id: ID!) {
          draftOrder(id: $id) {
            id
            name
            invoiceUrl
            status
            tags
            order {
              id
              fullyPaid
              displayFinancialStatus
            }
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

      resp = client.query(query: query_draft_order, variables: { id: gid })
      return [:error, nil] unless resp.code == 200

      body = resp.body
      draft = body&.dig("data", "draftOrder")
      return [:found, draft] unless draft.nil?

      gone = body.is_a?(Hash) && body["errors"].blank? && body["data"].is_a?(Hash) && body["data"].key?("draftOrder")
      [gone ? :gone : :error, nil]
    end

    # draftOrderDelete for the draft `gid`. It checks nothing about whose draft it is, so it stays out of the models'
    # API. Its only callers: #destroy_shopify_draft_order below (a record's own stored id, after
    # #ensure_can_use_draft_order: lockers, memberships) and JobOrder::DraftDeletion (job orders, the sweep).
    # `user_errors_out`: optional Array that receives Shopify's userErrors.
    # True when Shopify reports it deleted the draft. Fail closed: anything but HTTP 200 raises.
    def self.delete(gid, user_errors_out: nil)
      delete_draft_order = <<~QUERY
        mutation draftOrderDelete($input: DraftOrderDeleteInput!) {
          draftOrderDelete(input: $input) {
            deletedId
            userErrors {
              field
              message
            }
          }
        }
      QUERY

      resp = client.query(query: delete_draft_order, variables: { input: { id: gid } })
      raise "Received HTTP #{resp.code} when deleting shopify draft order" unless resp.code == 200

      user_errors_out&.concat(Array(resp.body&.dig("data", "draftOrderDelete", "userErrors")))
      resp.body&.dig("data", "draftOrderDelete", "deletedId").present?
    end
  end

  def self.target_tag
    Rails.env.production? ? "makerepo" : "makerepo_#{Rails.env}"
  end

  class_methods do
    def draft_order_processable?(tag)
      tags = if tag.is_a?(String)
               tag.split(',').map(&:strip)
             elsif tag.is_a?(Array)
               tag.map(&:to_s).map(&:strip)
             else
               []
             end

      tags.include?(draft_order_operating_tag)
    end

    def draft_order_operating_tag
      "#{ShopifyConcern.target_tag}_#{shopify_draft_order_key_name}"
    end

    def shopify_draft_order_key_name
      raise NotImplementedError, "Must define shopify_draft_order_key_name on model including ShopifyConcern"
    end
  end

  def shopify_is_paid
    shopify_draft_order&.dig('order', 'fullyPaid') == true
  end

  def shopify_draft_order_key_name
    self.class.shopify_draft_order_key_name
  end

  private

  # Stores the id of a draft Shopify just created from `line_items` (the exact items sent). A model that needs to
  # remember what the draft was built from overrides this (JobOrder stores a fingerprint in the same UPDATE).
  def store_shopify_draft_order_id(new_id, _line_items)
    update_column(:shopify_draft_order_id, new_id)
  end

  included do
    private

    def draft_order_metafields(gid = :auto)
      if gid == :auto
        ensure_can_use_draft_order
        gid = shopify_draft_order_id
      end
      return [] if gid.blank?

      query = <<~QUERY
        query NodeMetafields($ownerId: ID!) {
          node(id: $ownerId) {
            ... on Order {
              metafields(first: 50) {
                edges {
                  node {
                    namespace
                    key
                    value
                  }
                }
              }
            }
            ... on DraftOrder {
              metafields(first: 50) {
                edges {
                  node {
                    namespace
                    key
                    value
                  }
                }
              }
            }
          }
        }
      QUERY

      resp = shopify_admin_client.query(query: query, variables: { ownerId: gid })

      resp.body&.dig("data", "node", "metafields", "edges")&.map { |n| n["node"] } || []
    end

    def shopify_admin_client
      ShopifyConcern::DraftOrders.client
    end

    def ensure_can_use_draft_order
      unless has_attribute?("shopify_draft_order_id")
        raise "Model #{self.class.name} does not define a shopify_draft_order_id column"
      end

      raise "Key name must not be blank" if shopify_draft_order_key_name.blank?

      unless respond_to?(:shopify_draft_order_line_items, true)
        raise "Line items method shopify_draft_order_line_items must be defined"
      end
    end

    def shopify_draft_order
      ensure_can_use_draft_order

      if shopify_draft_order_id.blank?
        create_shopify_draft_order
      else
        fetch_shopify_draft_order
      end
    end

    # `user_errors_out`: optional Array that receives Shopify's userErrors (the boolean contract is unchanged).
    def destroy_shopify_draft_order(user_errors_out: nil)
      ensure_can_use_draft_order
      return false if shopify_draft_order_id.blank?

      deleted = ShopifyConcern::DraftOrders.delete(shopify_draft_order_id, user_errors_out: user_errors_out)
      update_column(:shopify_draft_order_id, nil)
      deleted
    end

    def fetch_shopify_draft_order
      fetch_shopify_draft_order_result.last
    end

    # One getDraftOrder query that tells three outcomes apart: [:found, draft], [:gone, nil] (HTTP 200 with
    # `draftOrder: null` and no GraphQL errors) and [:error, nil] (non-200 or an error payload). Exceptions
    # propagate (unknown, never "gone").
    def fetch_shopify_draft_order_result(gid = shopify_draft_order_id)
      ShopifyConcern::DraftOrders.fetch_result(gid)
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

      variables = shopify_draft_order_input
      resp = shopify_admin_client.query(
        query: create_draft_order,
        variables: variables
      )

      unless resp.code == 200
        raise "Network error: Received HTTP #{resp.code} while creating draft order"
      end

      user_errors = resp.body&.dig("data", "draftOrderCreate", "userErrors")
      if user_errors.present?
        messages = user_errors.map { |e| e["message"] }.join(", ")
        raise "Shopify Draft Order Creation Failed: #{messages}"
      end

      draft_order_data = resp.body&.dig("data", "draftOrderCreate", "draftOrder")
      unless draft_order_data
        raise "No draft order data received: #{resp.body}"
      end

      store_shopify_draft_order_id(draft_order_data["id"], variables.dig(:input, :lineItems))
      fetch_shopify_draft_order
    end

    # The tags of the draft: the environment's operating tag (what the paid webhook routes on). A model may add
    # a marker that identifies the record the draft was made for (JobOrder: "job_order:<id>").
    def shopify_draft_order_tags
      [self.class.draft_order_operating_tag]
    end

    def shopify_draft_order_input
      {
        input: {
          note: "Generated by makerepo",
          tags: shopify_draft_order_tags,
          lineItems: send(:shopify_draft_order_line_items),
          metafields: [
            {
              namespace: "makerepo",
              key: "#{shopify_draft_order_key_name}_db_reference",
              value: id.to_s,
              type: "number_integer"
            }
          ]
        }
      }
    end
  end
end