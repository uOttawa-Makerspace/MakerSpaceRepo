# frozen_string_literal: true

require "rails_helper"

# Browser crawl over one page per view template. A Rack probe requests every
# crawlable GET route (see spec/support/page_crawl.rb), notes which template
# rendered each 200 HTML answer and keeps the first page for each template:
# signed in as the admin, plus the pages only a guest reaches (login, sign-up,
# password reset). Each kept page is opened in headless Chrome, audited with
# axe (see spec/support/axe_audit.rb) and must log no SEVERE console error
# outside spec/support/js_error_allowlist.rb. The no-500 breadth check for all
# roles lives in spec/requests/page_crawl_spec.rb.
#
# Known axe violations are listed in page_crawl_axe_baseline.yml (template =>
# rule => violating nodes). The list may only shrink: a violation it does not
# list fails the example, and so does an entry that no longer occurs, so the
# list is pruned as pages are fixed. The colour rules are left out (colour is a
# design decision), and so are the documents inside frames (outside sites,
# stored PDFs, SCORM packages): the frame elements themselves are checked. The
# browser resolves no outside host (see --host-resolver-rules in
# spec/support/system.rb), so embedded videos, their thumbnails and wiki frames
# stay offline.
RSpec.describe "Page crawl (browser, one page per view template)", type: :system do
  let!(:admin) { create(:user, :admin) }

  before do
    stub_shopify_admin!
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
  end

  def baseline_file = Rails.root.join("spec/system/page_crawl_axe_baseline.yml")

  # template => path of the first crawlable route that answers 200 with HTML
  # rendered by it, for a fresh probe session (signed in as the admin when asked).
  def template_pages(world, sign_in:)
    probe = ActionDispatch::Integration::Session.new(Rails.application)
    sign_in_probe(probe) if sign_in
    PageCrawl.routes.each_with_object({}) do |route, pages|
      path = crawlable_path(route, world) or next
      template = rendered_template(probe, path)
      pages[template || route.path_spec] ||= path if html_page?(probe.response)
    end
  end

  def crawlable_path(route, world)
    PageCrawl.fill(route, world).first unless PageCrawl.skip_reason(route)
  end

  def html_page?(response) = response.status == 200 && response.media_type == "text/html"

  # Signs in through the login form, with its CSRF token (forgery protection is on).
  def sign_in_probe(probe)
    probe.get login_path
    token = Nokogiri::HTML(probe.response.body).at_css("meta[name='csrf-token']")["content"]
    probe.post login_authentication_path,
               params: { username_email: admin.username, password: PageCrawl::PASSWORD, authenticity_token: token }
  end

  # Requests the path and returns the view that rendered the answer: the
  # outermost template, or the outermost partial when the action renders only a
  # partial; nil when no view rendered it (a file or a redirect).
  def rendered_template(probe, path)
    events = []
    rendered = /\Arender_(template|partial)\.action_view\z/
    ActiveSupport::Notifications.subscribed(->(event) { events << event }, rendered) { probe.get path }
    view = events.reverse.find { |e| e.name.start_with?("render_template") } || events.last
    views = Rails.root.join("app/views").to_s
    view&.payload&.dig(:identifier)&.delete_prefix("#{views}/")
  end

  # Opens each page; returns the axe rule counts and the console errors by template.
  def crawl(pages, found)
    pages.each do |template, path|
      visit path
      expect(page).to have_css("body")
      wait_for_page_settled
      violations = AxeAudit.record(AxeAudit.run(page, skip: AxeAudit::COLOUR_RULES, frames: false), path, template)
      found[:axe][template] = violations.map(&:rule).tally.sort.to_h if violations.any?
      messages = JsErrorCheck.collect(page).map { |e| e[:message] }
      found[:errors][path] = messages if messages.any?
    end
  end

  # Lines for each template and rule whose node count differs from the baseline.
  def baseline_changes(actual, baseline)
    (actual.keys | baseline.keys).sort.flat_map do |template|
      now = actual.fetch(template, {})
      was = baseline.fetch(template, {})
      (now.keys | was.keys).sort.filter_map do |rule|
        next if now[rule] == was[rule]

        "#{template}: #{rule} #{was[rule] || 0} -> #{now[rule] || 0} nodes"
      end
    end
  end

  def new_violation_details(actual, baseline)
    AxeAudit.violations.select { |v| actual.dig(v.label, v.rule).to_i > baseline.dig(v.label, v.rule).to_i }
            .map { |v| "  #{v.label} #{v.rule}: #{v.selector} #{v.html}" }
  end

  def write_actual(actual)
    dir = Rails.root.join(AxeAudit::REPORT_DIR)
    FileUtils.mkdir_p(dir)
    dir.join("page_crawl_axe_actual#{ENV['TEST_ENV_NUMBER']}.yml").write(actual.sort.to_h.to_yaml)
  end

  it "opens one page per view template without new axe violations or SEVERE console errors" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    world = PageCrawl::World.new(self)

    admin_pages = template_pages(world, sign_in: true)
    guest_pages = template_pages(world, sign_in: false).except(*admin_pages.keys)
    expect(admin_pages.size).to be > 150 # guard: the probe really found the templates
    expect(guest_pages.size).to be >= 2

    found = { axe: {}, errors: {} }
    crawl(guest_pages, found)
    log_in_as(admin)
    crawl(admin_pages, found)

    if ENV["CRAWL_REPORT"]
      seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      puts format("BROWSER CRAWL: %<pages>d templates (%<guest>d guest-only) in %<seconds>.1fs, axe %<axe>.1fs",
                  pages: admin_pages.size + guest_pages.size, guest: guest_pages.size, seconds:, axe: AxeAudit.seconds)
    end
    baseline = YAML.safe_load_file(baseline_file) || {}
    changes = baseline_changes(found[:axe], baseline)
    write_actual(found[:axe]) if changes.any?
    aggregate_failures do
      expect(changes).to be_empty, <<~MSG
        The axe results differ from #{baseline_file.relative_path_from(Rails.root)}:
        #{changes.join("\n")}
        New violations (fix them; the baseline only shrinks):
        #{new_violation_details(found[:axe], baseline).join("\n")}
        A count that went down is a fix: copy the lower counts from
        #{AxeAudit::REPORT_DIR}/page_crawl_axe_actual#{ENV['TEST_ENV_NUMBER']}.yml into the baseline.
      MSG
      expect(found[:errors]).to eq({})
    end
  end
end
