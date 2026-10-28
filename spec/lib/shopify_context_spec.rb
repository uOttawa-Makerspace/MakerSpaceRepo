# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/shopify_context")

# ShopifyContext.ensure_setup! is the single place that calls ShopifyAPI::Context.setup
# (boot initializer, ShopifyConcern, ShopifyService, ShopifyCartConcern). Credentials come
# from spec/support/shopify_http_helpers.rb's fake config (shpat_test_fake, fake-shop, 2025-01).
RSpec.describe ShopifyContext, :shopify_context do
  let(:reports) { [] }

  before do
    allow(Rails.error).to receive(:report) { |e, **opts| reports << [e, opts] }
    allow(Rails.logger).to receive(:warn)
  end

  def blank_context!
    %i[@api_key @api_secret_key @api_version].each { |iv| ShopifyAPI::Context.instance_variable_set(iv, "") }
    ShopifyAPI::Context.instance_variable_set(:@host, nil)
  end

  it "sets the Context up with exactly master's start_shopify_session arguments, and returns true" do
    expect(ShopifyAPI::Context).to receive(:setup).with(
      api_key: "fake_api_key", api_secret_key: "shpat_test_fake", host: "fake-shop.myshopify.com",
      is_embedded: false, is_private: true, api_version: "2025-01"
    )
    expect(described_class.ensure_setup!).to be(true)
  end

  it "configures a cold Context" do
    blank_context!
    expect(described_class.ensure_setup!).to be(true)
    expect(ShopifyAPI::Context.api_version).to eq("2025-01")
    expect(ShopifyAPI::Context.api_key).to eq("fake_api_key")
    expect(ShopifyAPI::Context.host).to eq("fake-shop.myshopify.com")
    expect(ShopifyAPI::Context.private?).to be(true)
    expect(ShopifyAPI::Context.embedded?).to be(false)
  end

  it "is idempotent: skips Context.setup when already set up with the same values" do
    described_class.ensure_setup!
    expect(ShopifyAPI::Context).not_to receive(:setup)
    expect(described_class.ensure_setup!).to be(true)
  end

  it "sets up again when the values changed" do
    described_class.ensure_setup!
    ShopifyAPI::Context.instance_variable_set(:@api_version, "2024-10")
    expect(ShopifyAPI::Context).to receive(:setup).once
    described_class.ensure_setup!
  end

  %i[api_key password shop_name api_version].each do |key|
    it "with #{key} missing: reports, logs, returns false, does not raise and does not call setup" do
      cfg = ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG.merge(key => nil)
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(cfg)
      expect(ShopifyAPI::Context).not_to receive(:setup)

      expect(described_class.ensure_setup!).to be(false)
      expect(reports.size).to eq(1)
      expect(reports.first.first).to be_a(ShopifyContext::MissingConfig)
      expect(reports.first.first.message).to include(key.to_s)
      expect(Rails.logger).to have_received(:warn).with(/#{key}/)
    end
  end

  it "with no shopify credentials section at all: reports and returns false" do
    allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(nil)
    expect(described_class.ensure_setup!).to be(false)
    expect(reports.size).to eq(1)
  end

  it "when Context.setup raises (e.g. unsupported version): reports, logs, returns false" do
    blank_context!
    allow(ShopifyAPI::Context).to receive(:setup).and_raise(ShopifyAPI::Errors::UnsupportedVersionError, "nope")
    expect(described_class.ensure_setup!).to be(false)
    expect(reports.first.first).to be_a(ShopifyAPI::Errors::UnsupportedVersionError)
    expect(Rails.logger).to have_received(:warn).with(/UnsupportedVersionError/)
  end

  describe ".start_session!" do
    it "ensures the Context is set up, then builds and activates a session for the configured shop" do
      expect(described_class).to receive(:ensure_setup!).and_call_original
      session = described_class.start_session!
      expect(session).to be_a(ShopifyAPI::Auth::Session)
      expect(session.shop).to eq("fake-shop.myshopify.com")
      expect(session.access_token == "shpat_test_fake").to be(true)
      expect(ShopifyAPI::Context.active_session).to equal(session)
    end

    it "primes a cold Context before the session is used" do
      blank_context!
      described_class.start_session!
      expect(ShopifyAPI::Context.api_version).to eq("2025-01")
    end

    it "is what ShopifyService, ShopifyConcern and ShopifyCartConcern delegate to" do
      sentinel = Object.new
      allow(described_class).to receive(:start_session!).and_return(sentinel)
      expect(ShopifyService.start_shopify_session).to equal(sentinel)
      expect(Membership.start_shopify_session).to equal(sentinel)
      expect(Class.new { include ShopifyCartConcern }.start_shopify_session).to equal(sentinel)
    end

    it "ShopifyService digs: a missing shopify section does not raise NoMethodError" do
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(nil)
      allow(Rails.application.credentials).to receive(:[]).with(:test).and_return({})
      expect { ShopifyService.start_shopify_session }.not_to raise_error
    end
  end
end
