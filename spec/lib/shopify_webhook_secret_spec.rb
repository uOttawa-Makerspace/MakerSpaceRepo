# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/shopify_webhook_secret")

# config/initializers/shopify_app.rb delegates the secret choice to this unit.
# Outside test/development a missing credential resolves to nil (never to a public
# string); the app still boots and CustomWebhooksController refuses webhooks (503).
RSpec.describe ShopifyWebhookSecret do
  it "returns the credential when present, in every environment" do
    %w[production staging development test].each do |env|
      expect(described_class.resolve(env: env, credential: "real-secret")).to eq("real-secret")
    end
  end

  %w[production staging qa].each do |env|
    it "resolves to nil (no test_secret fallback, no raise) in #{env} when the credential is nil" do
      expect(described_class.resolve(env: env, credential: nil)).to be_nil
    end

    it "resolves to nil in #{env} when the credential is blank" do
      expect(described_class.resolve(env: env, credential: "  ")).to be_nil
    end

    it "accepts a symbol env (#{env})" do
      expect(described_class.resolve(env: env.to_sym, credential: nil)).to be_nil
    end
  end

  %w[test development].each do |env|
    it "falls back to test_secret in #{env}" do
      expect(described_class.resolve(env: env, credential: nil)).to eq("test_secret")
    end
  end

  it ".configured? is true only for a present secret" do
    expect(described_class.configured?("x")).to be(true)
    expect(described_class.configured?(nil)).to be(false)
    expect(described_class.configured?("")).to be(false)
  end

  it "is the resolver the initializer applied (the live test config equals the resolver output)" do
    expected = described_class.resolve(
      env: Rails.env, credential: Rails.application.credentials.dig(Rails.env.to_sym, :shopify, :webhook)
    )
    expect(ShopifyApp.configuration.secret).to eq(expected)
  end

  describe "config/initializers/shopify_app.rb" do
    let(:initializer) { Rails.root.join("config/initializers/shopify_app.rb") }

    around do |example|
      original = ShopifyApp.configuration.secret
      example.run
    ensure
      ShopifyApp.configuration.secret = original
    end

    def load_initializer_as(env, webhook_credential)
      creds = double("credentials")
      allow(creds).to receive(:dig).with(env.to_sym, :shopify, :webhook).and_return(webhook_credential)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(env.to_s))
      allow(Rails.application).to receive(:credentials).and_return(creds)
      load initializer
    end

    %w[production staging].each do |env|
      it "boots in #{env} with a nil webhook credential: secret stays nil (never test_secret) and a warning is logged" do
        ShopifyApp.configuration.secret = "sentinel"
        allow(Rails.logger).to receive(:warn)
        expect { load_initializer_as(env, nil) }.not_to raise_error
        expect(ShopifyApp.configuration.secret).to be_nil
        expect(Rails.logger).to have_received(:warn).with(/webhook secret is missing.*credentials\.#{env}\.shopify\.webhook.*503/).once
      end

      it "boots in #{env} with the credential, uses it as the HMAC secret and does not warn" do
        allow(Rails.logger).to receive(:warn)
        load_initializer_as(env, "whsec-from-credentials")
        expect(ShopifyApp.configuration.secret).to eq("whsec-from-credentials")
        expect(Rails.logger).not_to have_received(:warn).with(/webhook secret is missing/)
      end
    end

    it "uses the public test_secret fallback in development, without a warning" do
      allow(Rails.logger).to receive(:warn)
      load_initializer_as("development", nil)
      expect(ShopifyApp.configuration.secret).to eq("test_secret")
      expect(Rails.logger).not_to have_received(:warn).with(/webhook secret is missing/)
    end
  end
end
