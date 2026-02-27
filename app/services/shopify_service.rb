# Functional service to access shopify API responses. Intended for controllers
# to help fetch data for display and confirmation.

# Models shouldn't use this, mix in ShopifyConcern and provide the data
# it wants to get an invoice link

class ShopifyService
  def self.start_shopify_session
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

  def self.admin_client
    ShopifyAPI::Clients::Graphql::Admin.new(session: start_shopify_session)
  end

  def self.product(gid)
    # GraphQL: the job security oriented query service
    # gid looks like gid://shopify/Product/10478024917048

    # NOTE: This gets first 25 variants, if there's more (for some reason)
    # you'll need to bump this up.
    query = <<~QUERY
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

    response = admin_client.query(query:)
    puts response.body['data']
    response.body['data']['product']
  rescue StandardError => e
    Rails.logger.error e
    nil
  end

  def self.product_variants(gid)
    product(gid)['variants']['edges'].map { |edge| edge['node'] }
  end
end
