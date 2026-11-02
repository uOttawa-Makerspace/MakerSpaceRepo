# frozen_string_literal: true

require "rails_helper"

# Guard: the fake Shopify credentials apply to EVERY example, not just :shopify_context ones.
# This file is deliberately not in ShopifyContextIsolation::SPEC_FILES, so its examples are
# untagged, like spec/system/homepage_spec.rb's. Assertions are booleans/negatives so a failure
# can never print the real token.
RSpec.describe "Shopify credentials in an untagged example" do
  it "sees the fake token through dig and []" do
    expect(self.class.metadata[:shopify_context]).to be_blank
    creds = Rails.application.credentials
    expect(creds.dig(:test, :shopify, :password) == "shpat_test_fake").to be(true)
    expect(creds[:test][:shopify][:password] == "shpat_test_fake").to be(true)
    expect(creds.dig(:test, :shopify, :shop_name)).to eq("fake-shop")
  end

  it "never exposes a real shppa_/shpat_ admin token" do
    token = Rails.application.credentials.dig(:test, :shopify, :password).to_s
    expect(token.start_with?("shppa_")).to be(false)
  end
end
