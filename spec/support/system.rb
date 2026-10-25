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

  Capybara::Selenium::Driver.new(app, browser: :chrome, options:)
end

# Rails system specs bind the driver per example via driven_by; the
# ActionDispatch::SystemTestCase class-level call is not honoured by
# rspec-rails 8 — use a hook so every system spec gets our chromium config.
RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :headless_chrome, screen_size: [1600, 1000]
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
