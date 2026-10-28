# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/shopify_context")

# ShopifyContext.ensure_setup! is the single place that calls ShopifyAPI::Context.setup
# (boot initializer, ShopifyConcern, ShopifyService, ShopifyCartConcern). Credentials come
# from spec/support/shopify_http_helpers.rb's fake config (shpat_test_fake, fake-shop, 2025-01).
RSpec.describe ShopifyContext, :shopify_context do
  include ActiveSupport::Testing::TimeHelpers

  let(:reports) { [] }

  before do
    allow(Rails.error).to receive(:report) { |e, **opts| reports << [e, opts] }
    allow(Rails.logger).to receive(:warn)
    allow(described_class).to receive(:report_to_tracker?).and_return(true) # the reporting path; see "report environments"
  end

  describe "report environments" do
    def as_env(name)
      allow(described_class).to receive(:report_to_tracker?).and_wrap_original do |original, *|
        original.call(ActiveSupport::EnvironmentInquirer.new(name))
      end
    end

    before { allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return({}) }

    it "reports to the tracker only in production and staging" do
      allow(described_class).to receive(:report_to_tracker?).and_call_original
      states = %w[production staging test development].to_h { |e| [e, described_class.report_to_tracker?(ActiveSupport::EnvironmentInquirer.new(e))] }
      expect(states).to eq("production" => true, "staging" => true, "test" => false, "development" => false)
      expect(described_class.report_to_tracker?).to be(false) # defaults to Rails.env (test)
    end

    %w[test development].each do |env|
      it "in #{env}: missing config is a log warning only, no Rails.error report" do
        as_env(env)
        2.times { expect(described_class.ensure_setup!).to be(false) }
        expect(reports).to be_empty
        expect(Rails.logger).to have_received(:warn).with(/MissingConfig/).twice
      end
    end

    %w[production staging].each do |env|
      it "in #{env}: the failure is reported (and logged)" do
        as_env(env)
        described_class.ensure_setup!
        expect(reports.size).to eq(1)
        expect(Rails.logger).to have_received(:warn).with(/MissingConfig/)
      end
    end
  end

  def blank_context!
    %i[@api_key @api_secret_key @api_version].each { |iv| ShopifyAPI::Context.instance_variable_set(iv, "") }
    ShopifyAPI::Context.instance_variable_set(:@host, nil)
  end

  it "sets the Context up with exactly master's start_shopify_session arguments, and returns true" do
    blank_context! # a Context already holding these values (left by an earlier example) would skip setup
    expect(ShopifyAPI::Context).to receive(:setup).with(
      api_key: "fake_api_key", api_secret_key: "shpat_test_fake", host: "fake-shop.myshopify.com",
      is_embedded: false, is_private: true, api_version: "2025-01"
    )
    expect(described_class.ensure_setup!).to be(true)
  end

  it "configures a cold Context" do
    blank_context!
    expect(described_class.ensure_setup!).to be(true)
    expect(ShopifyAPI::Context.api_version).to eq("2025-01")
    expect(ShopifyAPI::Context.api_key).to eq("fake_api_key")
    expect(ShopifyAPI::Context.host).to eq("fake-shop.myshopify.com")
    expect(ShopifyAPI::Context.private?).to be(true)
    expect(ShopifyAPI::Context.embedded?).to be(false)
  end

  it "is idempotent: skips Context.setup when already set up with the same values" do
    described_class.ensure_setup!
    expect(ShopifyAPI::Context).not_to receive(:setup)
    expect(described_class.ensure_setup!).to be(true)
  end

  it "sets up again when the values changed" do
    described_class.ensure_setup!
    ShopifyAPI::Context.instance_variable_set(:@api_version, "2024-10")
    expect(ShopifyAPI::Context).to receive(:setup).once
    described_class.ensure_setup!
  end

  %i[api_key password shop_name api_version].each do |key|
    it "with #{key} missing: reports, logs, returns false, does not raise and does not call setup" do
      cfg = ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG.merge(key => nil)
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(cfg)
      expect(ShopifyAPI::Context).not_to receive(:setup)

      expect(described_class.ensure_setup!).to be(false)
      expect(reports.size).to eq(1)
      expect(reports.first.first).to be_a(ShopifyContext::MissingConfig)
      expect(reports.first.first.message).to include(key.to_s)
      expect(Rails.logger).to have_received(:warn).with(/#{key}/)
    end
  end

  it "with no shopify credentials section at all: reports and returns false" do
    allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(nil)
    expect(described_class.ensure_setup!).to be(false)
    expect(reports.size).to eq(1)
  end

  it "when Context.setup raises (e.g. unsupported version): reports, logs, returns false" do
    blank_context!
    allow(ShopifyAPI::Context).to receive(:setup).and_raise(ShopifyAPI::Errors::UnsupportedVersionError, "nope")
    expect(described_class.ensure_setup!).to be(false)
    expect(reports.first.first).to be_a(ShopifyContext::SetupFailed)
    expect(reports.first.first.message).to include("UnsupportedVersionError")
    expect(reports.first.first.message).not_to include("nope")
    expect(Rails.logger).to have_received(:warn).with(/UnsupportedVersionError/)
  end

  describe "never echoing a Context.setup error message (it can carry a secret)" do
    let(:digits) { 1_234_567_890_123_456 }
    let(:logged) { [] }

    before do
      allow(Rails.logger).to receive(:warn) { |m| logged << m.to_s }
      allow(Rails.logger).to receive(:info) { |m| logged << m.to_s }
      blank_context!
    end

    def everything_emitted
      logged + reports.flat_map { |e, opts| [e.message, e.class.name, opts.to_s] }
    end

    it "an Integer password (sorbet TypeError would echo it) is coerced to a String and sets up fine" do
      cfg = ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG.merge(password: digits, api_key: digits + 1)
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(cfg)
      expect(ShopifyAPI::Context).to receive(:setup).with(hash_including(api_secret_key: digits.to_s, api_key: (digits + 1).to_s)).and_call_original
      session = described_class.start_session!
      expect(session.access_token == digits.to_s).to be(true)
      expect(everything_emitted.join).not_to include(digits.to_s)
    end

    it "when Context.setup raises with a secret in its message, logs, reports and NotConfigured carry the class only" do
      allow(ShopifyAPI::Context).to receive(:setup).and_raise(TypeError, "Parameter 'api_secret_key': Expected type String, got #{digits}")
      expect { described_class.start_session! }.to raise_error(ShopifyContext::NotConfigured) { |e|
        expect(e.message).to include("TypeError")
        expect(e.message).not_to include(digits.to_s)
      }
      expect(reports.size).to eq(1)
      expect(logged).not_to be_empty
      expect(everything_emitted.join).to include("TypeError")
      expect(everything_emitted.join).not_to include(digits.to_s)
    end

    describe "what Airbrake receives for a Context.setup failure" do
      let(:secret) { "shpat_#{digits}" }
      let(:original) do
        raise TypeError, "Parameter 'api_secret_key': got #{secret}"
      rescue TypeError => e
        e
      end

      def chain(error)
        [error, *(error.cause ? chain(error.cause) : [])]
      end

      def expect_clean(error)
        expect(chain(error).flat_map { |e| [e.class.name, e.message, *e.backtrace.to_a] }.join("\n")).not_to include(secret)
        expect(error.cause).to be_nil
      end

      before { allow(ShopifyAPI::Context).to receive(:setup).and_raise(original) }

      it "reports a SetupFailed with the original backtrace, no cause, and no trace of the secret anywhere" do
        described_class.ensure_setup!
        reported, opts = reports.first
        expect(reported).to be_a(ShopifyContext::SetupFailed)
        expect(reported.backtrace).to be_present
        expect(reported.backtrace).to eq(original.backtrace)
        expect_clean(reported)
        expect(opts.to_s).not_to include(secret)
        expect(everything_emitted.join).not_to include(secret)
      end

      it "raises a NotConfigured without a cause, even from inside a caller's rescue block" do
        raised = begin
          begin
            raise ArgumentError, "caller's own failure #{secret}"
          rescue ArgumentError
            described_class.start_session!
          end
        rescue ShopifyContext::NotConfigured => e
          e
        end
        expect(raised).to be_a(ShopifyContext::NotConfigured)
        expect_clean(raised)
        expect(raised.message).to include("TypeError")
      end
    end

    it "the missing-config message names only key names" do
      cfg = ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG.merge(password: digits, api_key: nil)
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(cfg)
      expect { described_class.start_session! }.to raise_error(ShopifyContext::NotConfigured, /api_key/) { |e|
        expect(e.message).not_to include(digits.to_s)
      }
      expect(everything_emitted.join).not_to include(digits.to_s)
    end
  end

  describe "failure report throttle" do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return({})
    end

    it "reports a failure kind once per 10 minutes, logs every call, and reports again after the window" do
      travel_to(Time.zone.local(2026, 1, 1, 12, 0, 0)) do
        3.times { expect(described_class.ensure_setup!).to be(false) }
        expect(reports.size).to eq(1)
        expect(Rails.logger).to have_received(:warn).with(/MissingConfig/).once
        expect(Rails.logger).to have_received(:info).with(/MissingConfig.*throttled/).twice

        travel 9.minutes
        described_class.ensure_setup!
        expect(reports.size).to eq(1)

        travel 2.minutes
        described_class.ensure_setup!
        expect(reports.size).to eq(2)
      end
    end

    it "throttles each failure kind separately" do
      expect(described_class.ensure_setup!).to be(false)
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_call_original
      blank_context!
      allow(ShopifyAPI::Context).to receive(:setup).and_raise(ShopifyAPI::Errors::UnsupportedVersionError, "nope")
      expect(described_class.ensure_setup!).to be(false)
      expect(reports.map { |e, _| e.class }).to eq([ShopifyContext::MissingConfig, ShopifyContext::SetupFailed])
    end

    it "a different misconfiguration (other missing keys) still reports inside the window; the same one does not" do
      cfg = ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(cfg.merge(api_key: nil))
      2.times { described_class.ensure_setup! }
      expect(reports.size).to eq(1)

      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(cfg.merge(password: nil))
      2.times { described_class.ensure_setup! }
      expect(reports.size).to eq(2)

      # the same SET of missing keys is the same kind, however the credentials list them
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(cfg.merge(password: nil, api_key: nil))
      described_class.ensure_setup!
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(cfg.slice(:shop_name, :api_version))
      described_class.ensure_setup!
      expect(reports.size).to eq(3)
    end

    it "throttles Context.setup failures per underlying error class" do
      stub_shopify_credentials! # complete config again (this group's before hook blanks it)
      blank_context!
      allow(ShopifyAPI::Context).to receive(:setup).and_raise(ShopifyAPI::Errors::UnsupportedVersionError, "x")
      2.times { described_class.ensure_setup! }
      allow(ShopifyAPI::Context).to receive(:setup).and_raise(TypeError, "y")
      2.times { described_class.ensure_setup! }
      expect(reports.size).to eq(2)
    end

    it "shares ReportThrottle with the webhook-secret report" do
      expect(ShopifyContext::REPORT_THROTTLE).to be_a(ReportThrottle)
      expect(CustomWebhooksController::MISSING_SECRET_REPORT_THROTTLE).to be_a(ReportThrottle)
    end
  end

  describe ".start_session!" do
    it "ensures the Context is set up, then builds and activates a session for the configured shop" do
      blank_context!
      session = described_class.start_session!
      expect(ShopifyAPI::Context.api_version).to eq("2025-01")
      expect(session).to be_a(ShopifyAPI::Auth::Session)
      expect(session.shop).to eq("fake-shop.myshopify.com")
      expect(session.access_token == "shpat_test_fake").to be(true)
      expect(ShopifyAPI::Context.active_session).to equal(session)
    end

    it "reads the credentials once per call and builds the session from that same validated config" do
      first = ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG
      second = first.merge(shop_name: "other-shop", password: "shpat_second")
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(first, second)
      session = described_class.start_session!
      expect(session.shop).to eq("fake-shop.myshopify.com")
      expect(session.access_token == "shpat_test_fake").to be(true)
      expect(Rails.application.credentials).to have_received(:dig).with(:test, :shopify).once
    end

    it "keeps no failure in thread-local state" do
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return({})
      allow(Rails.logger).to receive(:warn)
      expect { described_class.start_session! }.to raise_error(ShopifyContext::NotConfigured)
      expect(Thread.current.key?(:shopify_context_failure)).to be(false)
    end

    it "primes a cold Context before the session is used" do
      blank_context!
      described_class.start_session!
      expect(ShopifyAPI::Context.api_version).to eq("2025-01")
    end

    it "is what ShopifyService, ShopifyConcern and ShopifyCartConcern delegate to" do
      sentinel = Object.new
      allow(described_class).to receive(:start_session!).and_return(sentinel)
      expect(ShopifyService.start_shopify_session).to equal(sentinel)
      expect(Membership.start_shopify_session).to equal(sentinel)
      expect(Class.new { include ShopifyCartConcern }.start_shopify_session).to equal(sentinel)
    end

    it "ShopifyService digs: a missing shopify section raises NotConfigured, not NoMethodError" do
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(nil)
      allow(Rails.application.credentials).to receive(:[]).with(:test).and_return({})
      expect { ShopifyService.start_shopify_session }.to raise_error(ShopifyContext::NotConfigured)
    end

    describe "when the Context cannot be set up" do
      before { allow(Rails.logger).to receive(:warn) }

      %i[api_key password shop_name api_version].each do |key|
        it "raises NotConfigured naming the missing #{key} and makes no HTTP request" do
          cfg = ShopifyHttpHelpers::FAKE_SHOPIFY_CONFIG.merge(key => nil)
          allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(cfg)
          expect(ShopifyAPI::Clients::Graphql::Admin).not_to receive(:new)

          expect { described_class.start_session! }.to raise_error(ShopifyContext::NotConfigured, /missing .*#{key}/) { |e|
            expect(e.message).not_to include("shpat_test_fake")
            expect(e.message).not_to include("fake_api_key")
          }
          expect(a_request(:any, /myshopify/)).not_to have_been_made
        end
      end

      it "raises NotConfigured with the setup error class (never its message) when Context.setup raises" do
        blank_context!
        allow(ShopifyAPI::Context).to receive(:setup).and_raise(ShopifyAPI::Errors::UnsupportedVersionError, "nope")
        expect { described_class.start_session! }
          .to raise_error(ShopifyContext::NotConfigured, /UnsupportedVersionError/) { |e| expect(e.message).not_to include("nope") }
      end

      it "with no shopify section at all raises NotConfigured, not NoMethodError" do
        allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return(nil)
        expect { described_class.start_session! }.to raise_error(ShopifyContext::NotConfigured)
      end

      it "a draft order creation surfaces the error and posts nothing to /admin/api//graphql.json" do
        allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return({})
        membership = create(:membership, user: create(:user, :regular_user), membership_tier: create(:membership_tier, duration: 30, internal_price: 1, external_price: 2), status: "pending")
        expect { membership.checkout_link }.to raise_error(ShopifyContext::NotConfigured)
        expect(a_request(:any, /graphql/)).not_to have_been_made
      end
    end
  end

  describe "thread safety" do
    it "two threads calling ensure_setup! on a cold Context run Context.setup exactly once" do
      blank_context!
      entered = Queue.new
      release = Queue.new
      calls = Concurrent::AtomicFixnum.new(0)
      allow(ShopifyAPI::Context).to receive(:setup).and_wrap_original do |original, **args|
        calls.increment
        entered << :in
        release.pop # hold the first setup open until the second thread has had every chance to race in
        original.call(**args)
      end

      first = Thread.new { described_class.ensure_setup! }
      entered.pop # first thread is inside Context.setup, Context still cold
      second = Thread.new { described_class.ensure_setup! }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5
      sleep 0.01 until second.status == "sleep" && (calls.value > 1 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline)
      2.times { release << :go } # unblocks the first, and the second too if the mutex is missing

      expect([first.value, second.value]).to eq([true, true])
      expect(calls.value).to eq(1)
    ensure
      2.times { release << :go } if release
      [first, second].compact.each { |t| t.join(2) }
    end
  end

  # The global before hook (spec/support/shopify_http_helpers.rb) resets both report throttles, so
  # no example resets them by hand. Defined order: the second example runs after the first used the throttle.
  describe "global throttle reset", order: :defined do
    it "first use of the missing-secret throttle in a run is allowed" do
      expect(CustomWebhooksController.report_missing_secret?).to be(true)
      expect(CustomWebhooksController.report_missing_secret?).to be(false)
    end

    it "is allowed again in the next example (the before hook reset it)" do
      expect(CustomWebhooksController.report_missing_secret?).to be(true)
    end
  end
end
