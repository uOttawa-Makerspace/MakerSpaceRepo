# frozen_string_literal: true

# ShopifyAPI::Context and ShopifyApp.configuration are process-global. Examples that prime
# the Context (ShopifyContext.ensure_setup!, ShopifyService.start_shopify_session, draft
# orders), blank it, re-load config/initializers/*.rb or re-run the ShopifyApp.configure
# block would otherwise leak that state into every example that runs after them (random
# order => flakes). Examples tagged :shopify_context get ALL instance variables of both
# objects, and the thread-local active session, snapshotted before and restored after.
#
# Files that touch Shopify are tagged below by path; tag any other example or group with
# `:shopify_context` explicitly. spec/lib/shopify_context_isolation_spec.rb proves the restore.
module ShopifyContextIsolation
  SPEC_FILES = %w[
    controllers/custom_webhooks_controller_spec controllers/memberships_spec
    lib/shopify_context_spec lib/shopify_webhook_secret_spec lib/shopify_context_isolation_spec
    models/concerns_shopify_concern_spec models/job_order_spec models/locker_rental_spec models/membership_spec
    requests/job_orders_request_spec requests/locker_orders_paid_webhook_spec requests/locker_rentals_request_spec
    requests/memberships_request_spec requests/page_crawl_spec requests/shop_orders_paid_webhook_spec
    requests/shopify_http_contract_spec requests/static_pages_request_spec requests/stripe_webhook_gaps_request_spec
    system/checkout_spec system/journeys/locker_journey_spec system/page_crawl_spec
  ].freeze

  Snapshot = Struct.new(:context_ivars, :config_ivars, :active_session, :rest_loader)

  def self.targets
    [ShopifyAPI::Context, ShopifyApp.configuration]
  end

  def self.ivars_of(object)
    object.instance_variables.to_h do |iv|
      value = object.instance_variable_get(iv)
      [iv, value.is_a?(Array) || value.is_a?(Hash) || value.is_a?(String) ? value.dup : value]
    end
  end

  def self.snapshot
    Snapshot.new(ivars_of(ShopifyAPI::Context), ivars_of(ShopifyApp.configuration),
                 ShopifyAPI::Context.active_session,
                 ShopifyAPI::Context.instance_variable_get(:@rest_resource_loader))
  end

  def self.restore_ivars(object, saved)
    (object.instance_variables - saved.keys).each { |iv| object.remove_instance_variable(iv) }
    saved.each { |iv, value| object.instance_variable_set(iv, value) }
  end

  def self.restore(snap)
    loader_changed = ShopifyAPI::Context.instance_variable_get(:@rest_resource_loader) != snap.rest_loader
    restore_ivars(ShopifyAPI::Context, snap.context_ivars)
    restore_ivars(ShopifyApp.configuration, snap.config_ivars)
    # Context.setup swaps the REST resource loader; bring the original version's resources back.
    version = snap.context_ivars[:@api_version]
    ShopifyAPI::Context.load_rest_resources(api_version: version) if loader_changed && version.present?
    snap.active_session ? ShopifyAPI::Context.activate_session(snap.active_session) : ShopifyAPI::Context.deactivate_session
  end
end

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/(#{Regexp.union(ShopifyContextIsolation::SPEC_FILES).source})\.rb\z}) do |meta|
    meta[:shopify_context] = true unless meta.key?(:shopify_context) # `shopify_context: false` opts out
  end

  config.around(:each, :shopify_context) do |example|
    snapshot = ShopifyContextIsolation.snapshot
    example.run
  ensure
    ShopifyContextIsolation.restore(snapshot) if snapshot
  end
end
