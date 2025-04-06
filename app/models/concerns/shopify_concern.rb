# frozen_string_literal: true

module ShopifyConcern
  extend ActiveSupport::Concern

  # Tag to identify staging/dev from prod
  def self.target_tag
    Rails.env.production? ? "makerepo" : "makerepo_#{Rails.env}"
  end

  class_methods do
    def start_shopify_session
      shopify_api_key =
        Rails.application.credentials[Rails.env.to_sym][:shopify][:api_key]
      shopify_password =
        Rails.application.credentials[Rails.env.to_sym][:shopify][:password]
      shopify_shop_name =
        Rails.application.credentials[Rails.env.to_sym][:shopify][:shop_name]
      shopify_api_version =
        Rails.application.credentials[Rails.env.to_sym][:shopify][:api_version]

      session =
        ShopifyAPI::Auth::Session.new(
          shop: "#{shopify_shop_name}.myshopify.com",
          access_token: shopify_password
        )

      ShopifyAPI::Context.setup(
        api_key: shopify_api_key,
        api_secret_key: shopify_password,
        host: "#{shopify_shop_name}.myshopify.com",
        is_embedded: false, # Not embedded in the Shopify admin UI
        is_private: true,
        api_version: shopify_api_version
      )

      # Activate session to be used in all API calls
      # session must be type `ShopifyAPI::Auth::Session`
      ShopifyAPI::Context.activate_session(session)

      session
    end
  end

  included do
    # NOTE: keep these methods private, if you need to access them from outside
    # then you're doing it wrong

    private

    # Authenticated a shopify session and returns it
    def start_shopify_session
      self.class.start_shopify_session
    end

    # Models that use this method must:
    # have a column called 'shopify_draft_order_id'
    # have a method called 'shopify_draft_order_line_items'
    # have a method called 'shopify_draft_order_key_name'
    def ensure_can_use_draft_order
      unless has_attribute? "shopify_draft_order_id"
        raise "Model does not define a shopify_draft_order_id column"
      end

      raise "Key name must not be blank" if shopify_draft_order_key_name.blank?
      if shopify_draft_order_line_items.blank?
        raise "Line items must not be blank"
      end
    end

    # Find a shopify draft order by metadata reference
    # FIXME: wrap in a API cache block
    def shopify_draft_order
      ensure_can_use_draft_order

      if shopify_draft_order_id.blank?
        create_shopify_draft_order
      else
        fetch_shopify_draft_order
      end
    end

    # Returns true if successfully deleted
    def destroy_shopify_draft_order
      ensure_can_use_draft_order

      return false if shopify_draft_order_id.blank?

      start_shopify_session
      admin_client =
        ShopifyAPI::Clients::Graphql::Admin.new(
          session: ShopifyAPI::Context.active_session
        )

      delete_draft_order = <<~QUERY
      mutation draftOrderDelete($input: DraftOrderDeleteInput!) {
        draftOrderDelete(input: $input) {
          deletedId
        }
      }
      QUERY

      input = { input: { id: shopify_draft_order_id } }

      resp = admin_client.query(query: delete_draft_order, variables: input)
      unless resp.code == 200
        raise "Received HTTP #{resp.code} when deleting shopify draft order: #{resp.body}"
      end

      update(shopify_draft_order_id: nil)
      # deletedId is nil if nothing was deleted
      resp.body.dig("data", "draftOrderDelete", "deletedId").present?
    end

    def fetch_shopify_draft_order
      start_shopify_session
      admin_client =
        ShopifyAPI::Clients::Graphql::Admin.new(
          session: ShopifyAPI::Context.active_session
        )
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

      resp = admin_client.query(query: query_draft_order)
      unless resp.code == 200
        raise "Network Error: HTTP #{resp.code} while fetching shopify draft order"
      end

      resp.body["data"]["draftOrder"]
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
      admin_client =
        ShopifyAPI::Clients::Graphql::Admin.new(
          session: ShopifyAPI::Context.active_session
        )

      resp =
        admin_client.query(
          query: create_draft_order,
          variables: shopify_draft_order_input
        )

      unless resp.code == 200
        raise "Network error: Received HTTP #{resp.code} while creating draft order"
      end

      unless resp.body.dig "data", "draftOrderCreate", "draftOrder"
        raise "No data received: #{resp.body}"
      end

      # save ID in database
      update(
        shopify_draft_order_id:
          resp.body["data"]["draftOrderCreate"]["draftOrder"]["id"]
      )
      fetch_shopify_draft_order
    end

    def shopify_draft_order_input
      {
        input: {
          note: "Generated by makerepo",
          tags: [ShopifyConcern.target_tag, shopify_draft_order_key_name],
          lineItems: shopify_draft_order_line_items,
          # metafields to track this rental ID inside the webhook handler
          metafields: [
            {
              namespace: "makerepo",
              key: "#{shopify_draft_order_key_name}_db_reference",
              value: id.to_s, # attach this ID to the draft order
              # https://shopify.dev/docs/apps/build/custom-data/metafields/list-of-data-types
              type: "number_integer"
            }
          ]
        }
      }
    end
  end

  # Returns a string to prefix the id metafield
  def shopify_draft_order_key_name
    raise "Did not define shopify_draft_order_key_name on model implementing concern"
  end

  def shopify_draft_order_line_items
    raise "Did not define shopify_draft_order_line_items on model implementing concern"
  end
end
