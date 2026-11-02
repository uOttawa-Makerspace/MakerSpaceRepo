# frozen_string_literal: true

require "rails_helper"

# Proves spec/support/shopify_context_isolation.rb: state mutated by a :shopify_context example
# (Context primed/blanked, ShopifyApp config rewritten, active session swapped) is gone for the
# example that runs after it. Defined order, so the second example really follows the first.
RSpec.describe "ShopifyAPI::Context / ShopifyApp isolation", :shopify_context, order: :defined do
  CONTEXT_KEYS = %i[@api_key @api_secret_key @api_version @host @is_private @is_embedded].freeze

  before(:all) do
    @baseline_context = CONTEXT_KEYS.to_h { |k| [k, ShopifyAPI::Context.instance_variable_get(k)] }
    @baseline_secret = ShopifyApp.configuration.secret
    @baseline_old_secret = ShopifyApp.configuration.old_secret
    @baseline_session = ShopifyAPI::Context.active_session
    @baseline_loader = ShopifyAPI::Context.instance_variable_get(:@rest_resource_loader)
  end

  it "first: mutates everything it can" do
    ShopifyAPI::Context.instance_variable_set(:@api_version, "")
    ShopifyContext.ensure_setup!
    ShopifyAPI::Context.setup(api_key: "leak", api_secret_key: "leak", host: "leak.myshopify.com",
                              is_embedded: true, is_private: false, api_version: "2025-01")
    ShopifyApp.configuration.secret = "leaked-secret"
    ShopifyApp.configuration.old_secret = "leaked-old"
    ShopifyAPI::Context.activate_session(ShopifyAPI::Auth::Session.new(shop: "leak.myshopify.com", access_token: "x"))
    ShopifyAPI::Context.instance_variable_set(:@leaked_extra, true)
    expect(ShopifyAPI::Context.api_key).to eq("leak")
  end

  it "second: sees the original Context, ShopifyApp config and session" do
    expect(CONTEXT_KEYS.to_h { |k| [k, ShopifyAPI::Context.instance_variable_get(k)] }).to eq(@baseline_context)
    expect(ShopifyApp.configuration.secret).to eq(@baseline_secret)
    expect(ShopifyApp.configuration.old_secret).to eq(@baseline_old_secret)
    expect(ShopifyAPI::Context.active_session).to eq(@baseline_session)
    expect(ShopifyAPI::Context.instance_variable_defined?(:@leaked_extra)).to be(false)
    if @baseline_context[:@api_version].present?
      expect(ShopifyAPI::Context.instance_variable_get(:@rest_resource_loader)).not_to be_nil
    end
  end
end
