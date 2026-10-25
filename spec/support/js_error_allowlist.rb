# frozen_string_literal: true

# JS console-error check for system specs (see spec/support/system.rb).
#
# Chrome's browser log is drained after every system example; any SEVERE entry
# fails the example unless an ALLOWLIST row matches it. A row needs:
#   path:    regex matched against the page path at the end of the example OR
#            the URL Chrome embeds in the log message (the script/request that
#            failed)
#   message: regex matched against the log message
#   id:      the D-JSnn defect ID (registered in doc/refactor/chunks/e2e-defects.md)
# Never add a blanket row (both regexes must be specific). Opt out per example
# with `js_errors: :allow` only when the example deliberately triggers an error.
module JsErrorCheck
  ALLOWLIST = [
    # WART(D-JS01): job_orders/new "Start Production" inline onclick is broken
    # HTML (see D-J19); the browser logs a SyntaxError when the page loads.
    { id: "D-JS01", path: %r{/job_orders/new\b}, message: /Uncaught SyntaxError: missing \) after argument list/ },
    # WART(D-JS02): locker_admin.js calls `bootstrap.Tooltip` but only the
    # `Tooltip` named import is bundled (no global `bootstrap`), so on any staff
    # page that has a data-bs-toggle="tooltip" (staff header) the turbo:load
    # handler throws before the "Indefinite" checkbox wiring runs.
    { id: "D-JS02", path: %r{/vite-test/assets/locker_admin-}, message: /locker_admin-[\w-]+\.js .*Uncaught ReferenceError: bootstrap is not defined/ },
    # WART(D-JS03): the 500 from GET /locker_rentals for an indefinite active
    # rental (D-E2E01) is logged by Chrome as a SEVERE resource error.
    { id: "D-JS03", path: %r{/locker_rentals(\z|\s)}, message: /locker_rentals - Failed to load resource: the server responded with a status of 500/ },
    # WART(D-JS04): pages load third-party scripts straight from the internet
    # (Cloudflare Turnstile, UserWay widget). The system browser resolves no
    # external host (see --host-resolver-rules in system.rb), so each logs a
    # DNS failure. Extend the host list only with the same kind of resource.
    { id: "D-JS04", path: %r{https://(challenges\.cloudflare\.com|cdn\.userway\.org)/}, message: /Failed to load resource: net::ERR_NAME_NOT_RESOLVED/ },
  ].freeze

  module_function

  def collect(page)
    path = begin
      URI.parse(page.current_url.to_s).path
    rescue StandardError
      ""
    end
    entries = begin
      page.driver.browser.logs.get(:browser)
    rescue StandardError
      []
    end
    entries.select { |e| e.level == "SEVERE" }.filter_map do |e|
      next if allowed?(path, e.message)

      { path:, message: e.message }
    end
  end

  def allowed?(path, message)
    ALLOWLIST.any? do |row|
      message.match?(row.fetch(:message)) &&
        (path.match?(row.fetch(:path)) || message.match?(row.fetch(:path)))
    end
  end
end
