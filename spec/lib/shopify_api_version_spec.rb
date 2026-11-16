# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/shopify_context")

# The Shopify Admin API version comes only from credentials.<env>.shopify.api_version. Specs see the fake config of
# spec/support/shopify_http_helpers.rb; the queries the app sends were checked against 2026-10, so the version the
# specs run against may not be older than that.
RSpec.describe "Shopify Admin API version", :shopify_context do
  let(:oldest_checked_version) { "2026-10" }

  def acceptable_version?(version)
    version.match?(/\A\d{4}-\d{2}\z/) && ShopifyAPI::AdminVersions::SUPPORTED_ADMIN_VERSIONS.include?(version) &&
      version >= oldest_checked_version
  end

  it "the configured version is a dated version the shopify_api gem supports, not older than 2026-10" do
    expect(ShopifyContext.configured_api_version).to eq(ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG[:api_version])
    expect(acceptable_version?(ShopifyContext.configured_api_version)).to be(true)
  end

  it "the check refuses an older version, a version string the gem does not know, unstable and an empty value" do
    expect(%w[2026-07 2025-10 2026-11 2026-1 unstable].push("").map { |v| acceptable_version?(v) }).to all(be(false))
  end

  it "the client sends every request to the version the credential gives" do
    allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify)
                                                          .and_return(ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG.merge(api_version: "2026-07"))
    seen = []
    stub_request(:post, "https://fake-shop.myshopify.com/admin/api/2026-07/graphql.json")
      .with { |req| seen << req.uri.path }
      .to_return(status: 200, headers: ShopifyHttpHelpers::JSON_HEADERS,
                 body: { data: { draftOrderDelete: { deletedId: "gid://shopify/DraftOrder/1", userErrors: [] } } }.to_json)

    expect(Payments::ShopifyAdapter::DraftOrders.delete("gid://shopify/DraftOrder/1")).to be(true)
    expect(seen).to eq(["/admin/api/2026-07/graphql.json"])
    expect(ShopifyAPI::Context.api_version).to eq("2026-07")
  end

  describe "the boot log" do
    let(:log) { StringIO.new }

    around do |example|
      logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(log)
      example.run
    ensure
      Rails.logger = logger
    end

    it "names the configured version" do
      load Rails.root.join("config/initializers/shopify_api.rb")
      expect(log.string).to include("[shopify_context] Shopify Admin API version 2026-10")
    end

    it "says when no version is configured" do
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify)
                                                            .and_return(ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG.except(:api_version))
      load Rails.root.join("config/initializers/shopify_api.rb")
      expect(log.string).to include("[shopify_context] Shopify Admin API version (not set)")
    end
  end
end
