# frozen_string_literal: true

require "webmock/rspec"

# No spec may reach the real network. Localhost stays open for the Capybara
# server (Puma) and chromedriver, which system specs talk to over HTTP.
#
# Anything else raises WebMock::NetConnectNotAllowedError; stub the specific
# call in the spec (see ShopSpecHelpers for the Shopify convention) or add a
# default stub below.
WebMock.disable_net_connect!(allow_localhost: true)

# StaticPagesController#home calls two external services on every homepage
# render (fetch_simpli_events and home_makerstore_links). Both fall back to an
# empty list when the service is unreachable, so the default stubs answer with
# empty lists: the page renders exactly as it does offline, without a socket.
RSpec.configure do |config|
  config.before(:each) do
    # Calendar feed hosts in specs are made-up names: have them resolve to a public address (IcsFetcher's own spec
    # calls the real resolver).
    allow(IcsFetcher).to receive(:resolve) do |host|
      literal = host.delete_prefix("[").delete_suffix("]")
      [IcsFetcher.ip_literal?(literal) ? literal : "93.184.216.34"]
    end

    stub_request(:get, %r{\Ahttps://simpli\.events/api/organizer/})
      .to_return(status: 200, body: { events: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    # Only the homepage's "collections(first: 8)" query is stubbed; any other
    # Shopify call still raises and must be stubbed by the spec that makes it.
    stub_request(:post, %r{\Ahttps://[^/]+\.myshopify\.com/admin/api/})
      .with(body: /collections\(first: 8\)/)
      .to_return(status: 200, body: { data: { collections: { nodes: [] } } }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end
end
