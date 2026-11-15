# frozen_string_literal: true

require "rails_helper"

# Only the Payments layer talks to Shopify: the Shopify SDK (ShopifyAPI, ShopifyApp), its configuration
# (ShopifyContext) and the old model-side draft code (ShopifyConcern) may be named only under app/models/payments/
# and in the Shopify initialisers. This scans the application code (app/, lib/, config/, db/, bin/, Rakefile) and fails
# on any other reference, comments included.
#
# ALLOWED lists what must stay for now, line by line, each file with the reason. The list only shrinks: a line that no
# longer exists fails too, so it is taken off when its reason goes away.
module PaymentsBoundary
  NAMES = /\b(?:ShopifyAPI|ShopifyApp|ShopifyContext|ShopifyConcern)\b/
  SCANNED = ["{app,lib,config,db}/**/*.{rb,rake,erb}", "bin/*", "Rakefile"].freeze
  PAYMENTS = %r{\Aapp/models/payments/}
  INITIALISERS = %w[config/initializers/shopify_api.rb config/initializers/shopify_app.rb].freeze

  # path => [reason, the exact (stripped) lines that may name the guarded names there]. A line is allowed by its text,
  # so a new SDK call in one of these files fails like anywhere else.
  ALLOWED = {
    "lib/shopify_context.rb" => [
      "configures ShopifyAPI::Context; the boot initialiser config/initializers/shopify_api.rb requires it before " \
      "app/ can be autoloaded, so it cannot live under app/models/payments/",
      [
        "# The ONE place that configures ShopifyAPI::Context (api key/secret, shop host, API version).",
        "module ShopifyContext",
        "super(\"credentials.\#{Rails.env}.shopify is missing \#{@keys.join(', ')}; ShopifyAPI::Context.setup skipped\")",
        "super(\"ShopifyAPI::Context.setup failed with \#{error_class_name}\")",
        "session = ShopifyAPI::Auth::Session.new(",
        "ShopifyAPI::Context.activate_session(session)",
        "ShopifyAPI::Context.setup(**args) unless current?(args)",
        "ShopifyAPI::Context.api_key == args[:api_key] &&",
        "ShopifyAPI::Context.api_secret_key == args[:api_secret_key] &&",
        "ShopifyAPI::Context.api_version == args[:api_version] &&",
        "ShopifyAPI::Context.host == args[:host] &&",
        "ShopifyAPI::Context.private? && !ShopifyAPI::Context.embedded?"
      ]
    ],
    "app/models/concerns/shopify_concern.rb" => [
      "the record-side draft bookkeeping of lockers, memberships and job orders (one stored draft id each), retired " \
      "as each product moves to Payments checkout records; it also defines MetafieldLookupFailed, " \
      "MetafieldLookupRejected and DraftOrderNotDeleted, whose class names processed_orders.last_error may record",
      [
        "module ShopifyConcern",
        "raise NotImplementedError, \"Must define shopify_draft_order_key_name on model including ShopifyConcern\""
      ]
    ],
    "app/models/locker_rental.rb" => ["lockers keep their stored draft id until they move to checkout records", ["include ShopifyConcern"]],
    "app/models/membership.rb" => ["memberships keep their stored draft id until they move to checkout records", ["include ShopifyConcern"]],
    "app/models/job_order.rb" => ["job orders keep their stored draft id until they move to checkout records", ["include ShopifyConcern"]]
  }.freeze

  module_function

  # [[path, stripped line], ...] for every line outside the Payments layer that names one of NAMES.
  def references
    SCANNED.flat_map { |glob| Dir[Rails.root.join(glob)] }.select { |f| File.file?(f) }.uniq.flat_map do |file|
      path = Pathname(file).relative_path_from(Rails.root).to_s
      next [] if path.match?(PAYMENTS) || INITIALISERS.include?(path)

      File.readlines(file).map(&:strip).grep(NAMES).map { |line| [path, line] }
    end
  end

  def allowed_lines = ALLOWED.flat_map { |path, (_reason, lines)| lines.map { |line| [path, line] } }
end

RSpec.describe "The Payments boundary" do
  let(:references) { PaymentsBoundary.references }

  it "names the Shopify SDK, its configuration and ShopifyConcern only in the Payments layer and the allowlist" do
    offenders = references - PaymentsBoundary.allowed_lines
    expect(offenders.map { |path, line| "#{path}: #{line}" }).to be_empty
  end

  it "has no stale allowlist entry" do
    expect(PaymentsBoundary.allowed_lines - references).to be_empty
  end

  it "allows a file's listed lines only, so a new SDK call in an allowlisted file is still an offender" do
    added = [["lib/shopify_context.rb", "ShopifyAPI::Clients::Graphql::Admin.new(session: session)"],
             ["app/models/concerns/shopify_concern.rb", "ShopifyAPI::Context.active_session"]]
    expect(added - PaymentsBoundary.allowed_lines).to eq(added)
  end

  it "gives every allowlist entry a reason" do
    expect(PaymentsBoundary::ALLOWED.values.map(&:first)).to all(be_present)
  end

  it "recognises the names it guards, and not their look-alikes" do
    expect(PaymentsBoundary::NAMES).to match("ShopifyAPI::Clients::Graphql::Admin.new")
    expect(PaymentsBoundary::NAMES).to match("include ShopifyApp::WebhookVerification")
    expect(PaymentsBoundary::NAMES).to match("ShopifyContext.start_session!")
    expect(PaymentsBoundary::NAMES).to match("ShopifyConcern::DraftRemoval.call(gid)")
    expect(PaymentsBoundary::NAMES).not_to match("ShopifyDraftSweep.run")
    expect(PaymentsBoundary::NAMES).not_to match("ShopifyWebhookSecret.configured?(secret)")
  end
end
