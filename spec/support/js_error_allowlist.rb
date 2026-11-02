# frozen_string_literal: true

# JS console-error check for system specs (see spec/support/system.rb).
#
# Chrome's browser log is drained after every system example; any SEVERE entry
# fails the example unless an ALLOWLIST row matches it. A row needs:
#   path:    regex matched against the page path at the end of the example OR
#            the URL Chrome embeds in the log message (the script/request that
#            failed)
#   message: regex matched against the log message
#   id:      a short label for the row
# Never add a blanket row (both regexes must be specific). Opt out per example
# with `js_errors: :allow` only when the example deliberately triggers an error.
module JsErrorCheck
  ALLOWLIST = [
    # job_orders/new "Start Production" inline onclick is broken
    # HTML; the browser logs a SyntaxError when the page loads.
    { id: "js-error-01", path: %r{/job_orders/new\b}, message: /Uncaught SyntaxError: missing \) after argument list/ },
    # locker_admin.js calls `bootstrap.Tooltip` but only the
    # `Tooltip` named import is bundled (no global `bootstrap`), so on any staff
    # page that has a data-bs-toggle="tooltip" (staff header) the turbo:load
    # handler throws before the "Indefinite" checkbox wiring runs.
    { id: "js-error-02", path: %r{/vite-test/assets/locker_admin-}, message: /locker_admin-[\w-]+\.js .*Uncaught ReferenceError: bootstrap is not defined/ },
    # the 500 from GET /locker_rentals for an indefinite active
    # rental is logged by Chrome as a SEVERE resource error.
    { id: "js-error-03", path: %r{/locker_rentals(\z|\s)}, message: /locker_rentals - Failed to load resource: the server responded with a status of 500/ },
    # pages load third-party scripts straight from the internet
    # (Cloudflare Turnstile, UserWay widget). The system browser resolves no
    # external host (see --host-resolver-rules in system.rb), so each logs a
    # DNS failure. Extend the host list only with the same kind of resource.
    { id: "js-error-04", path: %r{https://(challenges\.cloudflare\.com|cdn\.userway\.org|www\.youtube\.com)/}, message: /Failed to load resource: net::ERR_NAME_NOT_RESOLVED/ },
    # Found by the browser crawl (spec/system/page_crawl_spec.rb).
    # the 500s of the printers route (printers without sessions) break the
    # printer pages' fetch + JSON parse.
    { id: "js-error-05", path: %r{/printers/last_user_assigned_to_printer}, message: %r{last_user_assigned_to_printer - Failed to load resource: .* 500} },
    { id: "js-error-05", path: %r{/printers/staff_printers\b|/printer_types\b}, message: /(staff_printers|printer_types) 0:0 Uncaught \(in promise\) SyntaxError: Unexpected token '<'/ },
    # printer_issues.js binds a listener on an element the page lacks.
    { id: "js-error-06", path: %r{/assets/printer_issues-}, message: /printer_issues-[\w-]+\.js .*Cannot read properties of null \(reading 'addEventListener'\)/ },
    # the home/changelog hours widget calls /open_hours, which
    # fetches external ICS feeds (unreachable in tests: 500).
    { id: "js-error-07", path: %r{/open_hours}, message: %r{/open_hours - Failed to load resource: .* 500} },
    # announcements/new inline script uses a global flatpickr that is not loaded.
    { id: "js-error-08", path: %r{/admin/announcements/new}, message: /announcements\/new \d+:\d+ Uncaught ReferenceError: flatpickr is not defined/ },
    # admin_training_sessions.js and badges.js bind listeners on missing elements.
    { id: "js-error-09", path: %r{/assets/admin_training_sessions-}, message: /admin_training_sessions-[\w-]+\.js .*Cannot read properties of null \(reading 'addEventListener'\)/ },
    { id: "js-error-09", path: %r{/assets/badges-}, message: /badges-[\w-]+\.js .*Cannot read properties of null \(reading 'addEventListener'\)/ },
    # the badge SVG is rendered with empty width/height attributes.
    { id: "js-error-10", path: %r{/badges/\d+}, message: /Error: <svg> attribute (width|height): Unexpected end of attribute/ },
    # the admin calendar script requests its JSON endpoints with an
    # empty id (404) and then fails to parse the HTML.
    { id: "js-error-11", path: %r{/admin/(calendar|events)}, message: %r{/admin/(calendar/(utc_)?unavailabilities_json/|events/json/|calendar|calendar/imported_calendars_json/) .*(Failed to load resource: .* 404|Uncaught \(in promise\) SyntaxError)} },
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
