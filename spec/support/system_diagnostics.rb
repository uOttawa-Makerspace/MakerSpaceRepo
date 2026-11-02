# frozen_string_literal: true

# Failure diagnostics for system (browser) examples.
#
# When a system example fails, tmp/capybara/<example>.diagnostics.txt records
# what the app server and the browser were doing, so a "still on the edit form
# after submit" style failure can be classified from the artifact alone:
#   - the PATCH was slow          -> duration_ms of that request is large
#   - the PATCH was never sent    -> no such request in the table, none in flight
#   - it redirected elsewhere     -> status 302 and the location column
#   - it was still running        -> listed under "in flight at failure"
#
# Sections: current URL(s); timing of the last request; the last REQUEST_LIMIT
# requests (method, path, status, duration, redirect target, relative start);
# requests still in flight; the full browser console log; the tail of
# log/test.log written during the example (the test env logs at :warn, so it
# only holds warnings/errors; the request table comes from
# ActiveSupport::Notifications and does not depend on the log level).
#
# Requests are served by Puma threads inside the test process, so a global
# subscriber sees them; the buffer is reset before every system example.
module SystemDiagnostics
  REQUEST_LIMIT = 60
  LOG_TAIL_LINES = 60

  Request = Struct.new(:started, :finished, :method, :path, :status, :location, :duration_ms, :thread, keyword_init: true)

  @mutex = Mutex.new
  @requests = []
  @in_flight = {}
  @example_started = nil
  @log_offset = 0

  class << self
    attr_reader :example_started

    def install!
      return if @installed

      @installed = true
      ActiveSupport::Notifications.subscribe("start_processing.action_controller") do |_name, _start, _finish, id, payload|
        @mutex.synchronize { @in_flight[id] = [monotonic, payload[:method], strip_query(payload[:path])] }
      end
      ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, start, finish, id, payload|
        now = monotonic
        duration = (finish - start) * 1000.0
        status = payload[:status] || payload[:response]&.status
        location = strip_query(payload[:response]&.location) if payload.key?(:response)
        @mutex.synchronize do
          @in_flight.delete(id)
          @requests << Request.new(started: now - duration / 1000.0, finished: now, method: payload[:method],
                                   path: strip_query(payload[:path]), status: status, location: location,
                                   duration_ms: duration, thread: Thread.current.object_id.to_s(16))
          @requests.shift while @requests.size > REQUEST_LIMIT * 4
        end
      end
    end

    # CI uploads tmp/capybara on failure: never record query strings, which
    # can carry magic-link, pay and reset tokens.
    def strip_query(url)
      url&.split("?", 2)&.first
    end

    def reset!
      @mutex.synchronize do
        @requests.clear
        @in_flight.clear
      end
      @example_started = monotonic
      @log_offset = begin
        File.size(log_path)
      rescue StandardError
        0
      end
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def log_path
      Rails.root.join("log", "#{Rails.env}.log")
    end

    # Write the report for one browser session. `label` distinguishes the
    # default session from as_actor sessions.
    def write(example_name, page, label: "default")
      FileUtils.mkdir_p(Capybara.save_path)
      file = Capybara.save_path.join("#{example_name}.#{label}.diagnostics.txt")
      File.write(file, report(page, label))
      file
    rescue StandardError => e
      warn "system diagnostics could not be written: #{e.class}: #{e.message}"
      nil
    end

    def report(page, label)
      now = monotonic
      requests, in_flight = @mutex.synchronize { [@requests.last(REQUEST_LIMIT), @in_flight.values] }
      origin = @example_started || now
      out = []
      out << "== session: #{label}"
      out << "current URL: #{safe { strip_query(page.current_url) }}"
      out << "example running for: #{format('%.0f', (now - origin) * 1000)} ms"
      out << ""
      out << "== last request"
      last = requests.last
      if last
        out << "#{last.method} #{last.path} -> #{last.status} #{last.location}".strip
        out << format("started %.0f ms after the example began, took %.0f ms, finished %.0f ms before this report",
                      (last.started - origin) * 1000, last.duration_ms, (now - last.finished) * 1000)
      else
        out << "(no request was served during this example)"
      end
      out << ""
      out << "== requests (oldest first; t = ms since example start)"
      requests.each do |r|
        out << format("t=%7.0f  %-6s %-60s %s  %7.1f ms  %s", (r.started - origin) * 1000, r.method, r.path.to_s[0, 60],
                      r.status.inspect.ljust(4), r.duration_ms, r.location.to_s)
      end
      out << ""
      out << "== in flight at failure (started, never completed)"
      if in_flight.empty?
        out << "(none)"
      else
        in_flight.each { |t, m, p| out << format("t=%7.0f  %-6s %s  (running %.0f ms)", (t - origin) * 1000, m, p, (now - t) * 1000) }
      end
      out << ""
      out << "== browser console (all levels)"
      entries = safe(default: []) { page.driver.browser.logs.get(:browser) }
      out << "(empty)" if entries.empty?
      entries.each { |e| out << "[#{e.level}] #{e.message}" }
      out << ""
      out << "== tail of #{log_path.relative_path_from(Rails.root)} written during the example"
      out.concat(log_tail)
      # console messages and log lines embed full URLs as well
      out.join("\n").gsub(/\?[^\s"'<>]+/, "?[FILTERED]") << "\n"
    end

    def log_tail
      return ["(no log)"] unless File.exist?(log_path)

      text = File.open(log_path) do |f|
        f.seek([@log_offset, File.size(f)].min)
        f.read.to_s.scrub
      end
      lines = text.lines.map(&:chomp)
      lines.empty? ? ["(nothing logged)"] : lines.last(LOG_TAIL_LINES)
    end

    def safe(default: "(unavailable)")
      yield
    rescue StandardError => e
      default.is_a?(String) ? "#{default} (#{e.class})" : default
    end
  end
end

SystemDiagnostics.install!

RSpec.configure do |config|
  config.before(:each, type: :system) { SystemDiagnostics.reset! }

  # Declared after the hooks in system.rb; RSpec runs after-hooks in reverse
  # order, so this one runs first, before the console log is drained.
  config.after(:each, type: :system) do |example|
    next unless example.exception

    name = example.metadata[:full_description].gsub(/[^a-z0-9]+/i, "_").truncate(120)
    SystemDiagnostics.write(name, page)
  end
end
