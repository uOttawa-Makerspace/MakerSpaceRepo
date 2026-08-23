# frozen_string_literal: true

module ShopifyCartConcern
  extend ActiveSupport::Concern

  def self.target_tag
    Rails.env.production? ? "makerepo" : "makerepo_#{Rails.env}"
  end

  class_methods do
    def start_shopify_session
      config = Rails.application.credentials.dig(Rails.env.to_sym, :shopify) || {}

      session = ShopifyAPI::Auth::Session.new(
        shop: "#{config[:shop_name]}.myshopify.com",
        access_token: config[:password]
      )

      ShopifyAPI::Context.setup(
        api_key: config[:api_key],
        api_secret_key: config[:password],
        host: "#{config[:shop_name]}.myshopify.com",
        is_embedded: false,
        is_private: true,
        api_version: config[:api_version]
      )

      ShopifyAPI::Context.activate_session(session)
      session
    end
  end

  def shopify_checkout_link
    cart = shopify_cart
    cart&.dig("checkoutUrl")
  end

  included do
    private

    def ensure_can_use_cart
      unless has_attribute?("shopify_cart_id")
        raise "Model #{self.class.name} does not define a shopify_cart_id column"
      end

      raise "Key name must not be blank" if shopify_cart_key_name.blank?
      raise "Line items must not be blank" if shopify_cart_line_items.blank?
    end

    def shopify_cart
      ensure_can_use_cart

      if shopify_cart_id.blank?
        shopify_create_cart
      else
        shopify_fetch_cart || shopify_create_cart
      end
    end

    def shopify_create_cart
      create_cart_mutation = <<~QUERY
        mutation cartCreate($input: CartInput!) {
          cartCreate(input: $input) {
            cart {
              id
              checkoutUrl
              attributes {
                key
                value
              }
            }
            userErrors {
              field
              message
            }
          }
        }
      QUERY

      self.class.start_shopify_session
      storefront_client = ShopifyAPI::Clients::Graphql::Storefront.new(
        session: ShopifyAPI::Context.active_session
      )

      resp = storefront_client.query(
        query: create_cart_mutation,
        variables: { input: shopify_cart_input }
      )

      cart_data = resp.body.dig("data", "cartCreate", "cart")
      if cart_data.present?
        update_column(:shopify_cart_id, cart_data["id"])
      end

      cart_data
    end

    def shopify_fetch_cart
      query_cart = <<~QUERY
        query getCart($id: ID!) {
          cart(id: $id) {
            id
            checkoutUrl
            attributes {
              key
              value
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

      self.class.start_shopify_session
      admin_client = ShopifyAPI::Clients::Graphql::Admin.new(
        session: ShopifyAPI::Context.active_session
      )

      resp = admin_client.query(query: query_cart, variables: { id: shopify_cart_id })
      return nil unless resp.code == 200

      resp.body.dig("data", "cart")
    end

    def destroy_shopify_cart
      ensure_can_use_cart
      return false if shopify_cart_id.blank?

      self.class.start_shopify_session
      admin_client = ShopifyAPI::Clients::Graphql::Admin.new(
        session: ShopifyAPI::Context.active_session
      )

      delete_cart = <<~QUERY
        mutation cartDelete($input: CartDeleteInput!) {
          cartDelete(input: $input) {
            deletedId
          }
        }
      QUERY

      resp = admin_client.query(query: delete_cart, variables: { input: { id: shopify_cart_id } })
      return false unless resp.code == 200

      update_column(:shopify_cart_id, nil)
      resp.body.dig("data", "cartDelete", "deletedId").present?
    end

    def shopify_cart_input
      {
        attributes: [
          { key: "makerepo_target", value: ShopifyCartConcern.target_tag },
          { key: "#{shopify_cart_key_name}_db_reference", value: id.to_s }
        ],
        lines: shopify_cart_line_items
      }
    end
  end

  def shopify_cart_key_name
    raise NotImplementedError, "Must define shopify_cart_key_name on model including ShopifyCartConcern"
  end

  def shopify_cart_line_items
    raise NotImplementedError, "Must define shopify_cart_line_items on model including ShopifyCartConcern"
  end
end
