# frozen_string_literal: true

module Payments
  # Reads of the Shopify store's catalogue (a product, the homepage collections). Not payments, but Shopify: it sits
  # beside Payments::ShopifyAdapter so nothing outside app/models/payments/ talks to the Shopify SDK.
  module ShopifyCatalog
    # The makerspace's own store, which the homepage collections always come from.
    MAKERSTORE_SHOP = "uottawa-makerspace.myshopify.com"

    COLLECTIONS_QUERY = <<~QUERY
      query {
        collections(first: 8) {
          nodes {
            id
            handle
            description
            title
            image {
              url
            }
          }
        }
      }
    QUERY

    module_function

    # The product `gid` (gid://shopify/Product/...) with its first media and its first 25 variants; nil when Shopify
    # has no such product. Raises when Shopify does not answer.
    def product(gid)
      response = ShopifyAdapter.admin_client.query(query: product_query(gid))
      response.body['data']['product']
    end

    # NOTE: This gets first 25 variants, if there's more (for some reason) you'll need to bump this up.
    def product_query(gid)
      <<~QUERY
        query {
          product(id: "#{gid}") {
            id
            title
            status
            media(first: 1) {
              nodes {
                preview {
                  image {
                    url
                    altText
                  }
                }
              }
            }
            variants(first: 25) {
              nodes {
                id
                displayName
                title
                price
                sku
                media(first: 1) {
                  nodes {
                    preview {
                      image {
                        url
                        altText
                      }
                    }
                  }
                }
              }
            }
          }
        }
      QUERY
    end

    # The first 8 collections of the makerspace's own store ({ "id", "handle", "description", "title", "image" }
    # nodes), read with only the access token, so it needs no credentials shop_name, api_key or api_version.
    # ensure_setup! only primes Context.api_version for the client; it never raises and its result is ignored, so an
    # incomplete config behaves as it always did (boot priming, or the client's default). [] without a token or a
    # 200 answer. Raises what the client raises.
    def makerstore_collections
      access_token = (Rails.application.credentials[Rails.env.to_sym] || {}).dig(:shopify, :password)
      return [] if access_token.blank?

      ShopifyContext.ensure_setup!
      # to_s: sorbet type-checks access_token as String, and a YAML token of only digits parses as an Integer.
      session = ShopifyAPI::Auth::Session.new(shop: MAKERSTORE_SHOP, access_token: access_token.to_s)
      answer = ShopifyAdapter::Answer.new(ShopifyAdapter.admin_client(session: session).query(query: COLLECTIONS_QUERY))
      (answer.data("collections", "nodes") if answer.ok?) || []
    end
  end
end
