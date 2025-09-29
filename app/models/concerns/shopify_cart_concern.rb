# Concern to allow creating a cart with pre-existing products in inventory
# REVIEW: This is NOT complete, and has a lot of duplicated code with the other
# concern.
module ShopifyCartConcern
  extend ActiveSupport::Concern

  # Tag to identify staging/dev from prod
  def self.target_tag
    Rails.env.production? ? "makerepo" : "makerepo_#{Rails.env}"
  end

  # Pretty much copied from the other concern
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
    private

    def ensure_can_use_cart
      unless has_attribute? "shopify_cart_id"
        raise "Model does not define a shopify_cart_id column"
      end

      raise "Key name must not be blank" if shopify_cart_key_name.blank?
      if shopify_cart_line_items.blank?
        raise "Line items must not be blank"
      end
    end

    def shopify_cart
      ensure_can_use_cart

      # never made a cart before
      if shopify_cart_gid.blank?
        shopify_create_cart
      else
        # cart GID exists in database, fetch or create
        # because carts can expire after inactivity
        shopify_fetch_cart || shopify_create_cart
      end
    end

    # Fetch cart using GID stored
    def shopify_create_cart
      create_cart = <<~QUERY
mutation {
  cartCreate(input: $input) {
    cart {
      id
      attributes {
        key
        value
      }
      checkoutUrl
    }
  }
}
      QUERY

      start_shopify_session
      storefront_client =
        ShopifyAPI::Clients::Graphql::Storefront.new(
          session: ShopifyAPI::Context.active_session
        )

      resp =
        storefront_client.query(
          query: create_cart,
          variables: {
            input: shopify_cart_input
          }
        )
    end

    def shopify_fetch_cart
      query_cart = <<~QUERY
      query {
        cart(id: $id) {
          id
          attributes {
            key
            value
          }
          checkoutUrl
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

      start_shopify_session
      admin_client =
        ShopifyAPI::Clients::Graphql::Admin.new(
          session: ShopifyAPI::Context.active_session
        )

      resp = admin_client.query(query: query_cart)
      unless resp.code == 200
        raise "Network Error: HTTP #{resp.code} while fetching shopify cart"
      end

      resp.body["data"]["cart"]
    end

    def destroy_shopify_cart
      ensure_can_use_cart

      return false if shopify_cart_id.blank?

      start_shopify_session
      admin_client =
        ShopifyAPI::Clients::Graphql::Admin.new(
          session: ShopifyAPI::Context.active_session
        )

      delete_cart = <<~QUERY
      mutation cartDelete($input: CartDeleteInput!) {
        cartDelete(input: $input) {
          deletedId
        }
      }
      QUERY

      input = { input: { id: shopify_cart_id } }

      resp = admin_client.query(query: delete_cart, variables: input)
      unless resp.code == 200
        raise "Received HTTP #{resp.code} when deleting shopify cart: #{resp.body}"
      end

      update(shopify_cart_id: nil)
      # deletedId is nil if nothing was deleted
      resp.body.dig("data", "cartDelete", "deletedId").present?
    end

    # I have been told that cart attributes show up on orders. This entire
    # systems relies on the record ID showing up in the order attributes. This is
    # really hard to test or prove apparently
    def shopify_cart_input
      {
        tags: [ShopifyCartConcern.target_tag, shopify_cart_key_name],
        lines: shopify_cart_line_items,
        metafields: [
          {
            namespace: "makerepo",
            key: "#{shopify_cart_key_name}_db_reference",
            value: id.to_s, # attach this ID to the cart
            # https://shopify.dev/docs/apps/build/custom-data/metafields/list-of-data-types
            type: "number_integer"
          }
        ]
      }
    end
  end

  def shopify_cart_key_name
    raise "Did not define shopify_cart_key_name on model implementing concern"
  end

  def shopify_cart_line_items
    raise "Did not define shopify_cart_line_items on model implementing concern"
  end

  def shopify_checkout_link
    shopify_fetch_or_create_cart
  end
end
