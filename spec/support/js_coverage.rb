# frozen_string_literal: true

require "json"
require "securerandom"

# Browser-side line and branch coverage for the JS system specs. Active only
# with JS_COVERAGE=1, which builds the instrumented bundle (vite.config.ts) and
# makes the page keep its counters in window.__coverage__.
#
# The counters live in the page, so a full page load resets them. Two things
# keep them:
# - a script installed on every new document that, as the page unloads, adds
#   the counters to a total kept in sessionStorage (which survives same-origin
#   navigations in the tab, however they were started: visit, link, form post);
# - Turbo navigations keep the JS context and the counters, so they need
#   nothing.
# After every system example the stored total and the live counters are written
# to tmp/js-coverage/<worker>-<pid>-<random>.json. Several files are fine: nyc
# adds the counters of files that describe the same source.
module JsCoverage
  DIR = Rails.root.join("tmp", "js-coverage")
  STORAGE_KEY = "__js_coverage_total__"

  # Runs in the page on unload. Keeps the first full object per source file and
  # adds the counters of later loads to it.
  UNLOAD_SCRIPT = <<~JS.freeze
    addEventListener("pagehide", function () {
      try {
        var live = window.__coverage__;
        if (!live) return;
        var total = JSON.parse(sessionStorage.getItem("#{STORAGE_KEY}") || "{}");
        Object.keys(live).forEach(function (path) {
          var src = live[path], dst = total[path];
          if (!dst) { total[path] = JSON.parse(JSON.stringify(src)); return; }
          Object.keys(src.s).forEach(function (k) { dst.s[k] += src.s[k]; });
          Object.keys(src.f).forEach(function (k) { dst.f[k] += src.f[k]; });
          Object.keys(src.b).forEach(function (k) {
            src.b[k].forEach(function (n, i) { dst.b[k][i] += n; });
          });
        });
        sessionStorage.setItem("#{STORAGE_KEY}", JSON.stringify(total));
      } catch (e) {}
    });
  JS

  # The browser session is reused across examples, so the live counters are
  # zeroed once written; the next example then starts from nothing.
  ZERO_SCRIPT = <<~JS.freeze
    Object.values(window.__coverage__ || {}).forEach(function (c) {
      Object.keys(c.s).forEach(function (k) { c.s[k] = 0; });
      Object.keys(c.f).forEach(function (k) { c.f[k] = 0; });
      Object.keys(c.b).forEach(function (k) { c.b[k] = c.b[k].map(function () { return 0; }); });
    });
  JS

  TAKE_STORED_SCRIPT = <<~JS.freeze
    (function () {
      var total = sessionStorage.getItem("#{STORAGE_KEY}");
      sessionStorage.removeItem("#{STORAGE_KEY}");
      return total;
    })()
  JS

  class << self
    def enabled?
      ENV["JS_COVERAGE"] == "1"
    end

    # Installs the unload script once per browser session.
    def install(page)
      browser = page.driver.browser
      return if browser.instance_variable_get(:@js_coverage_installed)

      browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: UNLOAD_SCRIPT)
      browser.instance_variable_set(:@js_coverage_installed, true)
    rescue StandardError
      nil
    end

    # Writes what the example collected and empties the stored total.
    def flush(page)
      return if page.current_url.to_s.start_with?("about:", "data:") || page.current_url.blank?

      live = page.evaluate_script("window.__coverage__ ? JSON.stringify(window.__coverage__) : null")
      stored = page.evaluate_script(TAKE_STORED_SCRIPT)
      [live, stored].each { |json| write(json) }
      page.execute_script(ZERO_SCRIPT)
    rescue StandardError
      nil
    end

    private

    def write(json)
      return if json.nil? || json == "{}"

      FileUtils.mkdir_p(DIR)
      name = "#{ENV['TEST_ENV_NUMBER'].presence || 1}-#{Process.pid}-#{SecureRandom.hex(6)}.json"
      File.write(DIR.join(name), json)
    end
  end
end
