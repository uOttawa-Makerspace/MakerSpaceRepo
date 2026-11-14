# frozen_string_literal: true

require "rails_helper"

# Only the Payments layer talks to Shopify: the Shopify SDK (ShopifyAPI, ShopifyApp), its configuration
# (ShopifyContext) and the old model-side draft code (ShopifyConcern) may be named only under app/models/payments/
# and in the Shopify initialisers. This scans the application code (app/, lib/, config/) and fails on any other
# reference, comments included.
#
# ALLOWED_FILES and ALLOWED_LINES list what must stay for now, each with the reason. The lists only shrink: an entry
# that no longer matches anything fails too, so it is taken off when its reason goes away.
module PaymentsBoundary
  NAMES = /\b(?:ShopifyAPI|ShopifyApp|ShopifyContext|ShopifyConcern)\b/
  SCANNED = "{app,lib,config}/**/*.{rb,rake,erb}"
  PAYMENTS = %r{\Aapp/models/payments/}
  INITIALISERS = %w[config/initializers/shopify_api.rb config/initializers/shopify_app.rb].freeze

  ALLOWED_FILES = {
    "lib/shopify_context.rb" =>
      "configures ShopifyAPI::Context; the boot initialiser config/initializers/shopify_api.rb requires it before " \
      "app/ can be autoloaded, so it cannot live under app/models/payments/",
    "app/models/concerns/shopify_concern.rb" =>
      "the record-side draft bookkeeping of lockers, memberships and job orders (one stored draft id each), retired " \
      "as each product moves to Payments checkout records; it also defines MetafieldLookupFailed and " \
      "MetafieldLookupRejected, whose class names processed_orders.last_error records"
  }.freeze

  ALLOWED_LINES = {
    ["app/models/locker_rental.rb", "include ShopifyConcern"] => "lockers keep their stored draft id until they move to checkout records",
    ["app/models/membership.rb", "include ShopifyConcern"] => "memberships keep their stored draft id until they move to checkout records",
    ["app/models/job_order.rb", "include ShopifyConcern"] => "job orders keep their stored draft id until they move to checkout records"
  }.freeze

  module_function

  # [[path, stripped line], ...] for every line outside the Payments layer that names one of NAMES.
  def references
    Dir[Rails.root.join(SCANNED)].flat_map do |file|
      path = Pathname(file).relative_path_from(Rails.root).to_s
      next [] if path.match?(PAYMENTS) || INITIALISERS.include?(path)

      File.readlines(file).map(&:strip).grep(NAMES).map { |line| [path, line] }
    end
  end

  def allowed?(path, line) = ALLOWED_FILES.key?(path) || ALLOWED_LINES.key?([path, line])
end

RSpec.describe "The Payments boundary" do
  let(:references) { PaymentsBoundary.references }

  it "names the Shopify SDK, its configuration and ShopifyConcern only in the Payments layer and the allowlist" do
    offenders = references.reject { |path, line| PaymentsBoundary.allowed?(path, line) }
    expect(offenders.map { |path, line| "#{path}: #{line}" }).to be_empty
  end

  it "has no stale allowlist entry" do
    stale_files = PaymentsBoundary::ALLOWED_FILES.keys - references.map(&:first)
    stale_lines = PaymentsBoundary::ALLOWED_LINES.keys - references
    expect(stale_files + stale_lines).to be_empty
  end

  it "gives every allowlist entry a reason" do
    reasons = PaymentsBoundary::ALLOWED_FILES.values + PaymentsBoundary::ALLOWED_LINES.values
    expect(reasons).to all(be_present)
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
