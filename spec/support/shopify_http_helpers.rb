# frozen_string_literal: true

# Stubs the Shopify Admin GraphQL HTTP endpoint with WebMock while letting the
# REAL ShopifyAPI::Clients::Graphql::Admin client run (unlike
# ShopSpecHelpers::FakeShopifyAdmin, which replaces the client). Specs can then
# assert what actually goes on the wire: URL, access-token header, query text and
# variables.
module ShopifyHttpHelpers
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  def shopify_test_config
    Rails.application.credentials.dig(:test, :shopify)
  end

  def shopify_graphql_url
    cfg = shopify_test_config
    "https://#{cfg[:shop_name]}.myshopify.com/admin/api/#{cfg[:api_version]}/graphql.json"
  end

  # In production another code path (ShopifyService / ShopifyCartConcern) has
  # called ShopifyAPI::Context.setup before ShopifyConcern runs; ShopifyConcern
  # itself only activates the session. Do the same priming here so the URL carries
  # the API version regardless of spec order.
  def prime_shopify_context!
    ShopifyService.start_shopify_session
  end

  # Answers POSTs whose GraphQL query contains `marker` with `data`; returns an
  # array that fills with { headers:, body: (parsed JSON), url: } per request.
  def stub_shopify_graphql(marker, data, status: 200)
    seen = []
    stub_request(:post, shopify_graphql_url)
      .with do |req|
        body = JSON.parse(req.body)
        next false unless body["query"].to_s.include?(marker)

        seen << { headers: req.headers, body: body, url: req.uri.to_s.sub(":443/", "/") }
        true
      end
      .to_return(status: status, body: { data: data }.to_json, headers: JSON_HEADERS)
    seen
  end

  def stub_draft_order_create(draft_id)
    stub_shopify_graphql("mutation draftOrderCreate",
                         { "draftOrderCreate" => { "draftOrder" => { "id" => draft_id }, "userErrors" => [] } })
  end

  def stub_draft_order_fetch(draft_id, invoice_url:, fully_paid: false)
    stub_shopify_graphql("query getDraftOrder",
                         { "draftOrder" => { "id" => draft_id, "name" => "#D1", "invoiceUrl" => invoice_url,
                                             "status" => "OPEN",
                                             "order" => { "id" => "gid://shopify/Order/1", "fullyPaid" => fully_paid } } })
  end

  def expect_shopify_auth(request)
    expect(request[:url]).to eq(shopify_graphql_url)
    expect(request[:headers]["X-Shopify-Access-Token"]).to eq(shopify_test_config[:password])
    expect(request[:headers]["Content-Type"]).to eq("application/json")
  end
end

RSpec.configure do |config|
  config.include ShopifyHttpHelpers, type: :request
  config.include ShopifyHttpHelpers, type: :model
end
