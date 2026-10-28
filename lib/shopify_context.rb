# frozen_string_literal: true

# The ONE place that configures ShopifyAPI::Context (api key/secret, shop host, API version).
#
# The Shopify Admin client builds /admin/api/<version>/graphql.json from the Context, so a
# process that never ran Context.setup posts to /admin/api//graphql.json. Production's master
# set it up on every start_shopify_session; 3358306d0 dropped that and left only a
# ShopifyService call that staff lockers pages happened to trigger (D-S36).
#
# Called at boot (config/initializers/shopify_api.rb) AND before every Shopify session
# (via start_session!: ShopifyConcern, ShopifyService, ShopifyCartConcern; the homepage calls ensure_setup!), so a failed boot setup heals on the
# next draft order. Idempotent and cheap, and it never raises: failures are logged and
# reported in production/staging only (Rails.error, which Airbrake subscribes to) and ensure_setup! returns false.
require Rails.root.join("lib/report_throttle")

module ShopifyContext
  class MissingConfig < StandardError
    attr_reader :keys

    def initialize(keys)
      @keys = keys.map(&:to_sym).sort
      super("credentials.#{Rails.env}.shopify is missing #{@keys.join(', ')}; ShopifyAPI::Context.setup skipped")
    end
  end

  # Stands in for whatever Context.setup raised. sorbet's TypeErrors echo the offending VALUE
  # (an all-digit token, say), so the original message is never logged, reported or put in
  # NotConfigured: only its class name.
  class SetupFailed < StandardError
    attr_reader :error_class_name

    def initialize(error_class_name)
      @error_class_name = error_class_name
      super("ShopifyAPI::Context.setup failed with #{error_class_name}")
    end
  end

  # Raised by start_session! when the Context could not be set up (missing credentials keys, or
  # Context.setup raised). Message names the missing keys or the setup error class,
  # never the credentials or a Context.setup error message. Callers that already rescue Shopify errors rescue this the same way.
  class NotConfigured < StandardError; end

  # At most one failure report per kind per 10 minutes per process; every failure is still logged.
  # A kind is the error class plus, for MissingConfig, the sorted missing key names and, for
  # SetupFailed, the class Context.setup raised: a different misconfiguration still reports.
  REPORT_THROTTLE = ReportThrottle.new(interval: 10.minutes)

  SETUP_MUTEX = Mutex.new

  REQUIRED_KEYS = %i[api_key password shop_name api_version].freeze

  # Makes sure the Context is set up. Never raises: a failure is logged (and reported in
  # production/staging) and this returns false.
  def self.ensure_setup!
    _config, error = setup_context
    return true unless error

    failed(error)
  end

  # The ONE way to start a Shopify Admin/Storefront session: reads the credentials ONCE, makes sure
  # the Context is set up for them (raising NotConfigured when it cannot be), then builds the
  # session from that same validated config and activates it. ShopifyConcern, ShopifyCartConcern
  # and ShopifyService all call this.
  def self.start_session!
    config, error = setup_context
    if error
      failed(error)
      raise NotConfigured, "Shopify is not configured, not contacting the Admin API: #{error.class}: #{error.message}"
    end

    session = ShopifyAPI::Auth::Session.new(
      shop: "#{config[:shop_name]}.myshopify.com",
      access_token: config[:password].to_s
    )
    ShopifyAPI::Context.activate_session(session)
    session
  end

  # Reads the credentials once, validates them and runs Context.setup when needed.
  # Returns [config, nil] on success and [config, error] on failure; the error is MissingConfig
  # or SetupFailed, whose messages hold key names / an error class and never a value.
  def self.setup_context
    config = Rails.application.credentials.dig(Rails.env.to_sym, :shopify) || {}
    missing = REQUIRED_KEYS.reject { |key| config[key].present? }
    return [config, MissingConfig.new(missing)] unless missing.empty?

    args = {
      # to_s: sorbet type-checks these as String, and a YAML token of only digits parses as an Integer
      api_key: config[:api_key].to_s,
      api_secret_key: config[:password].to_s,
      host: "#{config[:shop_name]}.myshopify.com",
      is_embedded: false, # Not embedded in the Shopify admin UI
      is_private: true,
      api_version: config[:api_version].to_s
    }
    # Context.setup unloads and reloads the REST resource loader, so two Puma threads must never
    # both run it: check and setup are one critical section.
    SETUP_MUTEX.synchronize do
      ShopifyAPI::Context.setup(**args) unless current?(args)
    end
    [config, nil]
  rescue StandardError => e
    [config || {}, SetupFailed.new(e.class.name)]
  end
  private_class_method :setup_context

  def self.current?(args)
    ShopifyAPI::Context.api_key == args[:api_key] &&
      ShopifyAPI::Context.api_secret_key == args[:api_secret_key] &&
      ShopifyAPI::Context.api_version == args[:api_version] &&
      ShopifyAPI::Context.host == args[:host] &&
      ShopifyAPI::Context.private? && !ShopifyAPI::Context.embedded?
  end
  private_class_method :current?

  # Only production and staging page anyone about missing Shopify config. In test, development and
  # assets:precompile (no credentials) it is a log warning. A predicate so specs can stub it narrowly.
  def self.report_to_tracker?(env = Rails.env)
    %w[production staging].include?(env.to_s)
  end

  def self.throttle_kind(error)
    case error
    when MissingConfig then [error.class.name, *error.keys]
    when SetupFailed then [error.class.name, error.error_class_name]
    else [error.class.name]
    end
  end
  private_class_method :throttle_kind

  def self.failed(error)
    message = "[shopify_context] #{error.class}: #{error.message}"
    if !report_to_tracker?
      Rails.logger.warn(message)
    elsif REPORT_THROTTLE.allow?(throttle_kind(error))
      Rails.logger.warn(message)
      Rails.error.report(error, handled: true, severity: :error, context: { source: "shopify_context" })
    else
      Rails.logger.info("#{message} (report throttled)")
    end
    false
  end
  private_class_method :failed
end
