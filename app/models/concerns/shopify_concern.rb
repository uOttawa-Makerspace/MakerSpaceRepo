# frozen_string_literal: true

module ShopifyConcern
  extend ActiveSupport::Concern

  def self.target_tag
    Rails.env.production? ? "makerepo" : "makerepo_#{Rails.env}"
  end

  class_methods do
    def start_shopify_session
      shopify_config = Rails.application.credentials.dig(Rails.env.to_sym, :shopify) || {}

      session = ShopifyAPI::Auth::Session.new(
        shop: "#{shopify_config[:shop_name]}.myshopify.com",
        access_token: shopify_config[:password]
      )

      ShopifyAPI::Context.activate_session(session)
      session
    end

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

  included do
    private

    def draft_order_metafields(gid = :auto)
      if gid == :auto
        ensure_can_use_draft_order
        gid = shopify_draft_order_id
      end
      return [] if gid.blank?

      start_shopify_session

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

      resp = ShopifyAPI::Clients::Graphql::Admin
        .new(session: ShopifyAPI::Context.active_session)
        .query(query: query, variables: { ownerId: gid })

      resp.body&.dig("data", "node", "metafields", "edges")&.map { |n| n["node"] } || []
    end

    def start_shopify_session
      self.class.start_shopify_session
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

    def destroy_shopify_draft_order
      ensure_can_use_draft_order
      return false if shopify_draft_order_id.blank?

      start_shopify_session
      admin_client = ShopifyAPI::Clients::Graphql::Admin.new(
        session: ShopifyAPI::Context.active_session
      )

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

      resp = admin_client.query(query: delete_draft_order, variables: { input: { id: shopify_draft_order_id } })
      return false unless resp.code == 200

      update_column(:shopify_draft_order_id, nil)
      resp.body&.dig("data", "draftOrderDelete", "deletedId").present?
    end

    def fetch_shopify_draft_order
      start_shopify_session
      admin_client = ShopifyAPI::Clients::Graphql::Admin.new(
        session: ShopifyAPI::Context.active_session
      )

      query_draft_order = <<~QUERY
        query getDraftOrder($id: ID!) {
          draftOrder(id: $id) {
            id
            name
            invoiceUrl
            status
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

      resp = admin_client.query(query: query_draft_order, variables: { id: shopify_draft_order_id })
      return nil unless resp.code == 200

      resp.body&.dig("data", "draftOrder")
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
      admin_client = ShopifyAPI::Clients::Graphql::Admin.new(
        session: ShopifyAPI::Context.active_session
      )

      resp = admin_client.query(
        query: create_draft_order,
        variables: shopify_draft_order_input
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

      new_id = draft_order_data["id"]
      update_column(:shopify_draft_order_id, new_id)
      fetch_shopify_draft_order
    end

    def shopify_draft_order_input
      {
        input: {
          note: "Generated by makerepo",
          tags: [self.class.draft_order_operating_tag],
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