# frozen_string_literal: true

# The ONE place that configures ShopifyAPI::Context (api key/secret, shop host, API version).
#
# The Shopify Admin client builds /admin/api/<version>/graphql.json from the Context, so a
# process that never ran Context.setup posts to /admin/api//graphql.json. Production's master
# set it up on every start_shopify_session; 3358306d0 dropped that and left only a
# ShopifyService call that staff lockers pages happened to trigger (D-S36).
#
# Called at boot (config/initializers/shopify_api.rb) AND before every Shopify session
# (via start_session!: ShopifyConcern, ShopifyService, ShopifyCartConcern, StaticPagesController), so a failed boot setup heals on the
# next draft order. Idempotent and cheap, and it never raises: failures are logged and
# reported (Rails.error, which Airbrake subscribes to) and ensure_setup! returns false.
module ShopifyContext
  class MissingConfig < StandardError; end

  REQUIRED_KEYS = %i[api_key password shop_name api_version].freeze

  def self.ensure_setup!
    config = Rails.application.credentials.dig(Rails.env.to_sym, :shopify) || {}
    missing = REQUIRED_KEYS.reject { |key| config[key].present? }
    unless missing.empty?
      return failed(MissingConfig.new(
        "credentials.#{Rails.env}.shopify is missing #{missing.join(', ')}; ShopifyAPI::Context.setup skipped"
      ))
    end

    args = {
      api_key: config[:api_key],
      api_secret_key: config[:password],
      host: "#{config[:shop_name]}.myshopify.com",
      is_embedded: false, # Not embedded in the Shopify admin UI
      is_private: true,
      api_version: config[:api_version]
    }
    return true if current?(args)

    ShopifyAPI::Context.setup(**args)
    true
  rescue StandardError => e
    failed(e)
  end

  # The ONE way to start a Shopify Admin/Storefront session: dig the credentials, make sure the
  # Context is set up, build the session for them and activate it. ShopifyConcern,
  # ShopifyCartConcern, ShopifyService and StaticPagesController all call this.
  def self.start_session!
    config = Rails.application.credentials.dig(Rails.env.to_sym, :shopify) || {}
    ensure_setup!
    session = ShopifyAPI::Auth::Session.new(
      shop: "#{config[:shop_name]}.myshopify.com",
      access_token: config[:password]
    )
    ShopifyAPI::Context.activate_session(session)
    session
  end

  def self.current?(args)
    ShopifyAPI::Context.api_key == args[:api_key] &&
      ShopifyAPI::Context.api_secret_key == args[:api_secret_key] &&
      ShopifyAPI::Context.api_version == args[:api_version] &&
      ShopifyAPI::Context.host == args[:host] &&
      ShopifyAPI::Context.private? && !ShopifyAPI::Context.embedded?
  end
  private_class_method :current?

  def self.failed(error)
    Rails.logger.warn("[shopify_context] #{error.class}: #{error.message}")
    Rails.error.report(error, handled: true, severity: :error, context: { source: "shopify_context" })
    false
  end
  private_class_method :failed
end
