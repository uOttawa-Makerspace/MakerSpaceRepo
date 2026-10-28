# frozen_string_literal: true

# Stubs the Shopify Admin GraphQL HTTP endpoint with WebMock while letting the
# REAL ShopifyAPI::Clients::Graphql::Admin client run (unlike
# ShopSpecHelpers::FakeShopifyAdmin, which replaces the client). Specs can then
# assert what actually goes on the wire: URL, access-token header, query text and
# variables.
module ShopifyHttpHelpers
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  # Fixed fake Shopify config. config/credentials.yml.enc's test section holds a real-looking
  # access token; WebMock failure diffs print request headers, which would leak it into CI
  # logs. Every example sees these values instead (see the before hook below), and the
  # real credential is never read, asserted against or printed.
  FAKE_SHOPIFY_CONFIG = {
    shop_name: "fake-shop", api_key: "fake_api_key", password: "shpat_test_fake", api_version: "2025-01"
  }.freeze

  def shopify_test_config
    FAKE_SHOPIFY_CONFIG
  end

  # Replaces credentials.test.shopify (dig and [] access, as used by ShopifyConcern,
  # ShopifyService and StaticPagesController) with FAKE_SHOPIFY_CONFIG.
  def stub_shopify_credentials!
    creds = Rails.application.credentials
    env = Rails.env.to_sym
    allow(creds).to receive(:dig).and_wrap_original do |original, *keys|
      next original.call(*keys) unless keys.first(2) == [env, :shopify] && keys[2] != :webhook

      keys.size > 2 ? FAKE_SHOPIFY_CONFIG.dig(*keys.drop(2)) : FAKE_SHOPIFY_CONFIG
    end
    allow(creds).to receive(:[]).and_wrap_original do |original, key|
      value = original.call(key)
      next value unless key == env

      (value || {}).merge(shopify: FAKE_SHOPIFY_CONFIG.merge(webhook: value&.dig(:shopify, :webhook)))
    end
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
  config.include ShopifyHttpHelpers
  # EVERY example sees the fake Shopify credentials, tagged or not: config/credentials.yml.enc's
  # test section holds a real shppa_ token, and any untagged spec that reaches Shopify (the
  # homepage makerstore query, a WebMock failure diff) would otherwise print or send it.
  # The :shopify_context tag (shopify_context_isolation.rb) only snapshots/restores the Context.
  config.before(:each) do
    stub_shopify_credentials!
    ShopifyContext::REPORT_THROTTLE.reset! # failure reports are throttled per process; keep examples independent
  end
end
