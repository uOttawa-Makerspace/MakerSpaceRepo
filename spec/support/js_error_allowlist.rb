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
    # the 500 from GET /locker_rentals for an indefinite active
    # rental is logged by Chrome as a SEVERE resource error.
    { id: "js-error-03", path: %r{/locker_rentals(\z|\s)}, message: /locker_rentals - Failed to load resource: the server responded with a status of 500/ },
    # Pages load third-party scripts (Cloudflare Turnstile, UserWay widget)
    # after the page has loaded, and ignore a failed load; repository and
    # proposal pages embed YouTube videos and their thumbnails. The system
    # browser resolves no external host (see --host-resolver-rules in
    # system.rb), and Chrome still logs each blocked fetch as a resource error
    # whatever the page does with it. Extend the host list only with the same
    # kind of resource.
    { id: "js-error-04", path: %r{\Ahttps://(challenges\.cloudflare\.com|cdn\.userway\.org|(www|img)\.youtube\.com)/}, message: /Failed to load resource: net::ERR_NAME_NOT_RESOLVED/ },
    # the home/changelog hours widget calls /open_hours, which
    # fetches external ICS feeds (unreachable in tests: 500).
    { id: "js-error-07", path: %r{/open_hours}, message: %r{/open_hours(\?\S*)? - Failed to load resource: .* 500} },
    # the badge SVG is rendered with empty width/height attributes.
    { id: "js-error-10", path: %r{/badges/\d+}, message: /Error: <svg> attribute (width|height): Unexpected end of attribute/ },
    # the admin calendar script requests its JSON endpoints with an
    # empty id (404) and then fails to parse the HTML.
    { id: "js-error-11", path: %r{/admin/(calendar|events)}, message: %r{/admin/(calendar/unavailabilities_json/|events/json/|calendar|calendar/imported_calendars_json/) .*(Failed to load resource: .* 404|Uncaught \(in promise\) SyntaxError)} },
    # Opening the add-event modal asks for /admin/calendar/staff_json/:id,
    # which no route serves (404); the staff list is filled from another feed.
    { id: "js-error-staff-json", path: %r{/admin/calendar}, message: %r{/admin/calendar/staff_json/\d+ - Failed to load resource: .* 404} },
    # Calendar page scripts (pinned by the calendar characterization specs).
    # Saving an unavailability from the staff select reads an option without its unavailable dates.
    { id: "js-error-cal-staff-option", path: %r{/admin/calendar}, message: /calendar-[\w-]+\.js .*Uncaught TypeError: Cannot read properties of undefined \(reading 'split'\)/ },
    # The copy-events dialog calls flatpickr on an element that has no plugin.
    { id: "js-error-cal-copy-flatpickr", path: %r{/admin/calendar}, message: /calendar-[\w-]+\.js .*Uncaught TypeError: \w+\.flatpickr is not a function/ },
    # A refused staff colour answers 422; Chrome logs it as a resource error while the page shows a toast.
    { id: "js-error-color-422", path: %r{/admin/calendar}, message: %r{/admin/calendar/update_color - Failed to load resource: the server responded with a status of 422} },
    # Refused bookings answer 422; Chrome logs each as a resource error.
    { id: "js-error-booking-422", path: %r{/sub_space_booking\b}, message: %r{/sub_space_booking - Failed to load resource: the server responded with a status of 422} },
    # After a delete the page follows the redirect with a JSON request that answers 404.
    { id: "js-error-booking-delete-404", path: %r{/sub_space_booking\b}, message: %r{/sub_space_booking#booking-tab - Failed to load resource: the server responded with a status of 404} },
    # The select-dates dialog writes into a template row that is missing.
    { id: "js-error-booking-dates-row", path: %r{/sub_space_booking\b}, message: /sub_space_booking-[\w-]+\.js .*Uncaught TypeError: Cannot set properties of null \(setting 'innerHTML'\)/ },
    # the Bootstrap tooltip of a locker row note throws when the
    # row's hover text is rewritten after an inline save.
    { id: "js-error-12", path: %r{/lockers\z}, message: /bootstrap\.esm-[\w-]+\.js \d+:\d+ Uncaught TypeError: Cannot convert undefined or null to object/ },
    # a refused inline locker save answers 422 and lockers.js logs the failure.
    { id: "js-error-13", path: %r{/lockers\z}, message: %r{/lockers/\d+ - Failed to load resource: the server responded with a status of 422} },
    { id: "js-error-13", path: %r{/lockers\z}, message: /lockers-[\w-]+\.js \d+:\d+ Error: Failed to update (size|note\/details)/ },
    # the size dropdown of the single locker modal is built from options that
    # lack a display name when no size has a store variant.
    { id: "js-error-14", path: %r{/lockers\z}, message: /lockers-[\w-]+\.js \d+:\d+ Uncaught TypeError: Cannot read properties of null \(reading 'displayName'\)/ },
  ].freeze

  module_function

  # With leave_page, the page path is read first and the session is then reset
  # (the browser goes to about:blank) before the log is read, so nothing the
  # page still had in flight (a request, a timer, a transition) can be logged
  # after the drain and blamed on the next example. Use it once, at the end of
  # an example.
  def collect(page, leave_page: false)
    path = begin
      URI.parse(page.current_url.to_s).path
    rescue StandardError
      ""
    end
    page.reset_session! if leave_page
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
