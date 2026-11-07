# frozen_string_literal: true

# Helpers for the calendar page-script system specs (spec/system/js/calendars).
# The server clock is frozen by the example (travel_to); the browser keeps its
# real clock, so the visible week is chosen through the page's own "recall
# dates on refresh" localStorage key.
module CalendarJsHelpers
  WEEK_MIDDAY = "2027-03-16T12:00:00.000Z"

  # The instant (UTC, to the minute) the browser reads from a datetime-local
  # value: the browser parses it in its own time zone.
  def browser_utc(local_value)
    iso = page.evaluate_script("new Date('#{local_value}').toISOString()")
    Time.iso8601(iso).utc
  end

  # The admin calendar page attaches its event modal's handlers once the
  # script's own fetch has returned, which can be after the calendar title is
  # drawn. It then marks the modal ready (and enables "+ Add Event").
  def wait_for_admin_calendar_scripts
    expect(page).to have_css("#eventModal[data-ready='true']", visible: :all)
  end

  # Types into a datetime-local field the way a person would (Capybara fires
  # input and change for it).
  def fill_datetime(field, local_value)
    fill_in field, with: Time.strptime(local_value, "%Y-%m-%dT%H:%M")
  end

  def show_week_of_march_14(storage_key, path)
    visit "/robots.txt" # any page of the app origin will do: only its localStorage is needed
    page.execute_script("localStorage.#{storage_key} = '#{WEEK_MIDDAY}'")
    visit path
  end

  def calendar_event(title)
    page.find(".fc-event", text: title, visible: :all)
  end

  # The value a datetime-local field shows for an instant: the browser's own
  # local wall clock, as YYYY-MM-DDTHH:MM.
  def browser_local(time)
    page.evaluate_script(<<~JS)
      (function (d) {
        var p = function (n) { return String(n).padStart(2, "0"); };
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) +
          "T" + p(d.getHours()) + ":" + p(d.getMinutes());
      })(new Date("#{time.utc.iso8601}"))
    JS
  end

  # A one-event ICS feed (UTC times).
  def ics_feed(uid:, summary:, starts:, ends:, rrule: nil)
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//spec//EN", "BEGIN:VEVENT", "UID:#{uid}",
             "DTSTAMP:20270101T000000Z", "DTSTART:#{starts.utc.strftime('%Y%m%dT%H%M%SZ')}",
             "DTEND:#{ends.utc.strftime('%Y%m%dT%H%M%SZ')}", "SUMMARY:#{summary}"]
    lines << "RRULE:#{rrule}" if rrule
    (lines + ["END:VEVENT", "END:VCALENDAR"]).join("\r\n") + "\r\n"
  end

  # Waits (the Capybara way, no sleeping) until the block is truthy: for
  # server state that changes after a form submit.
  def eventually(&block)
    page.document.synchronize { raise Capybara::ExpectationNotMet, "condition not met" unless block.call }
  end

  # Opens the "Custom Values" accordion of the event or unavailability modal
  # and waits until it has finished opening.
  def open_custom_values
    find("#accordion .accordion-button").click
    expect(page).to have_css("#customFieldsCollapse.show")
  end

  def field_value(id)
    page.evaluate_script("document.getElementById('#{id}').value")
  end
end

RSpec.configure do |config|
  config.include CalendarJsHelpers, type: :system

  # `browser_zone: "America/Toronto"` runs the example with the browser's
  # time zone set through DevTools, so expectations built from browser-side
  # dates do not depend on the host zone. The override is cleared afterwards
  # because the Chrome session is reused.
  config.before(:each, :browser_zone, type: :system) do |example|
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: example.metadata[:browser_zone])
  end
  config.after(:each, :browser_zone, type: :system) do
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "")
  end
end
