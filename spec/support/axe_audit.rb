# frozen_string_literal: true

require "axe-rspec"
require "json"
require "fileutils"

# Automated accessibility audit (axe-core) for browser specs.
#
# `audit_accessibility` runs axe on the current page against the WCAG 2.0/2.1
# level A and AA rules, leaving out third-party widgets (UserWay, Cloudflare
# Turnstile) that the app does not control.
#
# Violations are collected per page and written to
# tmp/axe/report<TEST_ENV_NUMBER>.json at the end of the run and summarised on
# stdout. The example fails on any violation. Set AXE_STRICT=0 to only report.
module AxeAudit
  TAGS = %w[wcag2a wcag2aa wcag21a wcag21aa].freeze
  EXCLUDED = [
    ".userway_buttons_wrapper", "[data-uw-styling-context]", "[class*='userway']", "[id*='userway']",
    ".cf-turnstile", "iframe[src*='challenges.cloudflare.com']"
  ].freeze
  # FullCalendar's scrolling container is not keyboard focusable. Adding a
  # tabindex to it breaks the calendar's grid markup, so the rule is skipped
  # until the library fixes it.
  SKIPPED_RULES = %w[scrollable-region-focusable].freeze
  REPORT_DIR = "tmp/axe"

  Violation = Struct.new(:rule, :impact, :page, :label, :selector, :html, keyword_init: true)

  @violations = []
  @pages = 0
  @seconds = 0.0

  class << self
    attr_reader :violations, :pages, :seconds

    def strict? = !ENV["AXE_STRICT"].to_s.match?(/\A(0|false|no)\z/i)

    def run(page)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Axe::Configuration.instance.legacy_mode = true
      run = Axe::API::Run.new.according_to(*TAGS).excluding(*EXCLUDED).skipping(*SKIPPED_RULES)
      Axe::Core.new(page).call(run).results.violations
    ensure
      @seconds += Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end

    def record(rules, path, label)
      @pages += 1
      rules.flat_map do |rule|
        rule.nodes.map do |node|
          Violation.new(rule: rule.id.to_s, impact: rule.impact.to_s, page: path, label: label,
                        selector: Array(node.target).join(" "), html: node.html.to_s.squish[0, 200])
        end
      end.tap { |found| @violations.concat(found) }
    end

    def summary
      by_rule = @violations.group_by(&:rule).transform_values(&:size).sort_by { |_, n| -n }
      lines = ["AXE: #{@pages} pages audited in #{@seconds.round(1)}s, #{@violations.size} violating nodes, #{@violations.map(&:page).uniq.size} pages with violations"]
      by_rule.each { |rule, n| lines << format("  %-28s %4d nodes on %d pages", rule, n, @violations.select { |v| v.rule == rule }.map(&:page).uniq.size) }
      lines.join("\n")
    end

    def write_report
      return if @pages.zero?

      FileUtils.mkdir_p(Rails.root.join(REPORT_DIR))
      File.write(Rails.root.join(REPORT_DIR, "report#{ENV['TEST_ENV_NUMBER']}.json"),
                 JSON.pretty_generate(pages: @pages, violations: @violations.map(&:to_h)))
      puts "\n#{summary}\n(report: #{REPORT_DIR}/report#{ENV['TEST_ENV_NUMBER']}.json)"
    end
  end

  # Visible markers the app and its libraries show while content is still being
  # filled in: Turbo's busy attributes and progress bar, DataTables processing,
  # the Bootstrap spinner and the calendar pages' #spinner_container.
  LOADING_MARKERS = "[aria-busy='true'], turbo-frame[busy], .turbo-progress-bar, .dataTables_processing, " \
                    ".spinner-border, #spinner_container"

  # Waits (Capybara waiting, no sleeping) until the page has finished loading and
  # no loading marker is visible, so the audit never sees a half-rendered page.
  def wait_for_page_settled
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "document still loading" unless page.evaluate_script("document.readyState") == "complete"
    end
    expect(page).to have_no_css(LOADING_MARKERS)
  end

  def audit_accessibility(label = nil)
    wait_for_page_settled
    path = URI.parse(page.current_url).request_uri
    found = AxeAudit.record(AxeAudit.run(page), path, label)
    return if found.empty? || !AxeAudit.strict?

    raise "axe: #{found.size} accessibility violation(s) on #{path}:\n" +
          found.map { |v| "  #{v.rule} (#{v.impact}) #{v.selector}" }.join("\n")
  end
end

RSpec.configure do |config|
  config.include AxeAudit, type: :system
  config.after(:suite) { AxeAudit.write_report }
end
