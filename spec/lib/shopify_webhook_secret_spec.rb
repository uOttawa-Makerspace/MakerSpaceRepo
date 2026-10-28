# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/shopify_webhook_secret")

# config/initializers/shopify_app.rb delegates the secret choice to this unit.
RSpec.describe ShopifyWebhookSecret do
  it "returns the credential when present, in every environment" do
    %w[production staging development test].each do |env|
      expect(described_class.resolve(env: env, credential: "real-secret")).to eq("real-secret")
    end
  end

  %w[production staging].each do |env|
    it "raises at boot in #{env} when the credential is nil" do
      expect { described_class.resolve(env: env, credential: nil) }
        .to raise_error(ShopifyWebhookSecret::MissingSecret, /credentials\.#{env}\.shopify\.webhook/)
    end

    it "raises in #{env} when the credential is blank" do
      expect { described_class.resolve(env: env, credential: "  ") }
        .to raise_error(ShopifyWebhookSecret::MissingSecret)
    end

    it "accepts a symbol env (#{env})" do
      expect { described_class.resolve(env: env.to_sym, credential: nil) }
        .to raise_error(ShopifyWebhookSecret::MissingSecret)
    end
  end

  %w[test development].each do |env|
    it "falls back to test_secret in #{env}" do
      expect(described_class.resolve(env: env, credential: nil)).to eq("test_secret")
    end
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
      it "refuses to boot in #{env} with a nil webhook credential, and never installs test_secret" do
        ShopifyApp.configuration.secret = "sentinel"
        expect { load_initializer_as(env, nil) }.to raise_error(ShopifyWebhookSecret::MissingSecret, /Refusing to boot/)
        expect(ShopifyApp.configuration.secret).not_to eq("test_secret")
      end

      it "boots in #{env} with the credential and uses it as the HMAC secret" do
        load_initializer_as(env, "whsec-from-credentials")
        expect(ShopifyApp.configuration.secret).to eq("whsec-from-credentials")
      end
    end

    it "uses the public test_secret fallback in development" do
      load_initializer_as("development", nil)
      expect(ShopifyApp.configuration.secret).to eq("test_secret")
    end
  end
end
