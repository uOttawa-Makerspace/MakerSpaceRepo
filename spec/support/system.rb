# System (browser) test configuration.
# Provides look-and-feel characterization tests: pin that pages keep rendering
# the same after refactors (Bootstrap structure, navigation, key UI regions).
# Runs headless chromium inside the devcontainer (apk package `chromium`,
# which ships its own matching chromedriver on Alpine 3.24).

Capybara.javascript_driver = :headless_chrome
Capybara.server = :puma, { Silent: true }
Capybara.default_max_wait_time = 5
Capybara.save_path = Rails.root.join("tmp", "capybara")

Capybara.register_driver :headless_chrome do |app|
  # The devcontainer ships Alpine's /usr/bin/chromedriver; anywhere else (CI)
  # set CHROMEDRIVER_PATH, or let Selenium Manager find/download a matching one.
  chromedriver = ENV.fetch("CHROMEDRIVER_PATH", "/usr/bin/chromedriver")
  Selenium::WebDriver::Chrome::Service.driver_path = chromedriver if File.exist?(chromedriver)

  options = Selenium::WebDriver::Chrome::Options.new
  options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"].to_s != ""
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--window-size=1600,1000")
  # Hermetic browser: WebMock only guards Ruby HTTP, Chrome would otherwise
  # reach the real internet (Cloudflare Turnstile, CDNs, fonts). Everything
  # except the local Capybara server fails DNS, so results do not depend on
  # network access; the resulting console errors are allowlisted (D-JS04).
  options.add_argument("--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1")
  # Capture console output so JsErrorCheck (below) can fail examples on SEVERE
  # entries. Selenium 4.48 + chromedriver: the legacy goog:loggingPrefs
  # capability works and `driver.logs.get(:browser)` returns the entries.
  options.add_option("goog:loggingPrefs", { browser: "ALL" })

  Capybara::Selenium::Driver.new(app, browser: :chrome, options:)
end

# Rails system specs bind the driver per example via driven_by; the
# ActionDispatch::SystemTestCase class-level call is not honoured by
# rspec-rails 8 — use a hook so every system spec gets our chromium config.
RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :headless_chrome, screen_size: [1600, 1000]
  end

  # Fail on SEVERE browser console entries unless allowlisted
  # (spec/support/js_error_allowlist.rb). Opt out with `js_errors: :allow` on an
  # example that deliberately triggers an error.
  config.after(:each, type: :system) do |example|
    # Always drain: the Chrome session is reused across examples, so skipped
    # entries would otherwise leak into the next example.
    errors = JsErrorCheck.collect(page)
    next if example.metadata[:js_errors] == :allow
    next unless example.exception.nil?

    unless errors.empty?
      raise "Unallowlisted SEVERE browser console errors:\n" + errors.map { |e| "  [#{e[:path]}] #{e[:message]}" }.join("\n")
    end
  end

  # Save screenshots + page HTML on failure as CI artifacts (doc 9.5).
  config.after(:each, type: :system) do |example|
    if example&.exception
      name = example.metadata[:full_description].gsub(/[^a-z0-9]+/i, "_").truncate(120)
      begin
        page.save_screenshot(Capybara.save_path.join("#{name}.png"))
        page.save_page(Capybara.save_path.join("#{name}.html"))
      rescue StandardError
        nil
      end
    end
  end
end
