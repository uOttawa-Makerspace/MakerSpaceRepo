# frozen_string_literal: true

require "zlib"

# Browser crawl over one page per view template, split into SHARDS examples
# (spec/system/page_crawl/shard_*_spec.rb) so the parallel runner can spread it
# over its workers.
#
# Each shard builds the crawl world (spec/support/page_crawl.rb), and a Rack
# probe requests every crawlable GET route, notes which view rendered each 200
# HTML answer and keeps the first page for each view: signed in as the admin,
# plus the pages only a guest reaches (login, sign-up, password reset). The
# shard then opens the pages of the views it owns (a stable hash of the view's
# key) in headless Chrome, audits them with axe (spec/support/axe_audit.rb) and
# expects no SEVERE console error outside spec/support/js_error_allowlist.rb.
# The no-500 breadth check for all roles lives in
# spec/requests/page_crawl_spec.rb.
#
# Two committed lists, each checked by the shard that owns an entry:
# - templates.yml: every crawled view. It may only grow: a view that is no
#   longer crawled fails with its name, and a newly crawled one must be added.
# - axe_baseline.yml: known axe violations (view => rule => violating nodes).
#   It may only shrink: a violation it does not list fails, and so does a
#   listed one that no longer occurs.
#
# The colour rules are left out (colour is a design decision), and so are the
# documents inside frames (outside sites, stored PDFs, SCORM packages): the
# frame elements themselves are checked. Fragments (markup a page fetches and
# inserts) skip the rules about the document's title and language, which the
# host page provides. The server clock and Faker are fixed, so the world and
# the pages are the same on every run. The browser resolves no outside host
# (see --host-resolver-rules in spec/support/system.rb), so embedded videos,
# their thumbnails and wiki frames stay offline.
module PageCrawl
  # Settings and pure helpers of the browser crawl.
  module Browser
    SHARDS = 5
    DIR = "spec/system/page_crawl"
    CLOCK = Time.utc(2027, 3, 16, 16) # noon in Toronto
    FAKER_SEED = 20_270_316
    RENDERED = /\Arender_(template|partial)\.action_view\z/

    module_function

    def shard_of(key) = Zlib.crc32(key) % SHARDS

    def templates_file = Rails.root.join(DIR, "templates.yml")
    def baseline_file = Rails.root.join(DIR, "axe_baseline.yml")

    # The key of a rendered view: its path under app/views, under the app root,
    # or "gem-name:path" inside a gem. Anything else is an error, so a key is
    # never a machine-specific absolute path.
    def view_key(identifier)
      [Rails.root.join("app/views").to_s, Rails.root.to_s].each do |root|
        return identifier.delete_prefix("#{root}/") if identifier.start_with?("#{root}/")
      end
      gem = Gem.loaded_specs.values.find { |spec| identifier.start_with?("#{spec.full_gem_path}/") }
      raise ArgumentError, "view outside the app and its gems: #{identifier}" unless gem

      "#{gem.name}:#{identifier.delete_prefix("#{gem.full_gem_path}/")}"
    end

    # Lines for each key and rule whose node count differs from the baseline.
    def baseline_changes(actual, baseline)
      (actual.keys | baseline.keys).sort.flat_map do |key|
        now = actual.fetch(key, {})
        was = baseline.fetch(key, {})
        (now.keys | was.keys).sort.filter_map do |rule|
          "#{key}: #{rule} #{was[rule] || 0} -> #{now[rule] || 0} nodes" unless now[rule] == was[rule]
        end
      end
    end
  end

  # Example helpers for the crawl shards.
  module BrowserCrawl
    # key => [path, fragment] for the first crawlable route that answers 200
    # with HTML rendered by that view (or, when no view renders it, by the route
    # itself), for a fresh probe session signed in as the admin when asked. A
    # fragment is markup without an <html> element, which a page fetches and
    # inserts into itself.
    def crawl_pages(world, sign_in:)
      probe = ActionDispatch::Integration::Session.new(Rails.application)
      sign_in_probe(probe) if sign_in
      PageCrawl.routes.each_with_object({}) do |route, pages|
        path = crawlable_path(route, world) or next
        key = rendered_view(probe, path) || route.path_spec
        pages[key] ||= [path, fragment?(probe.response)] if html_page?(probe.response)
      end
    end

    def crawlable_path(route, world)
      PageCrawl.fill(route, world).first unless PageCrawl.skip_reason(route)
    end

    def html_page?(response) = response.status == 200 && response.media_type == "text/html"

    def fragment?(response) = !response.body.match?(/<html[\s>]/i)

    # Signs in through the login form, with its CSRF token (forgery protection is on).
    def sign_in_probe(probe)
      probe.get login_path
      token = Nokogiri::HTML(probe.response.body).at_css("meta[name='csrf-token']")["content"]
      probe.post login_authentication_path,
                 params: { username_email: admin.username, password: PageCrawl::PASSWORD, authenticity_token: token }
    end

    # Requests the path and returns the key of the view that rendered the
    # answer: the outermost template, or the outermost partial when the action
    # renders only a partial; nil when no view rendered it (a file or a redirect).
    def rendered_view(probe, path)
      events = []
      ActiveSupport::Notifications.subscribed(->(event) { events << event }, Browser::RENDERED) { probe.get path }
      view = events.reverse.find { |e| e.name.start_with?("render_template") } || events.last
      view && Browser.view_key(view.payload[:identifier])
    end

    # Opens each page; collects the axe rule counts by key and the console
    # errors by path. A fragment is audited without the rules about the document.
    def crawl(pages, found)
      pages.each do |key, (path, fragment)|
        visit path
        expect(page).to have_css("body")
        wait_for_page_settled
        skip = AxeAudit::COLOUR_RULES + (fragment ? AxeAudit::DOCUMENT_RULES : [])
        violations = AxeAudit.record(AxeAudit.run(page, skip:, frames: false), path, key)
        found[:axe][key] = violations.map(&:rule).tally.sort.to_h if violations.any?
        messages = JsErrorCheck.collect(page).map { |e| e[:message] }
        found[:errors][path] = messages if messages.any?
      end
    end

    def owned(list, shard) = list.select { |key| Browser.shard_of(key) == shard }

    def new_violation_details(actual, baseline)
      AxeAudit.violations.select { |v| actual.dig(v.label, v.rule).to_i > baseline.dig(v.label, v.rule).to_i }
              .map { |v| "  #{v.label} #{v.rule}: #{v.selector} #{v.html}" }
    end

    def report_file(shard) = Rails.root.join(AxeAudit::REPORT_DIR, "page_crawl_shard#{shard}.yml")

    def write_report(shard, crawled, axe)
      FileUtils.mkdir_p(Rails.root.join(AxeAudit::REPORT_DIR))
      report_file(shard).write({ "templates" => crawled.sort, "axe" => axe.sort.to_h }.to_yaml)
    end
  end
end

RSpec.shared_examples "a browser page crawl shard" do |shard|
  include PageCrawl::BrowserCrawl
  include ActiveSupport::Testing::TimeHelpers

  let!(:admin) { create(:user, :admin) }

  around do |example|
    Faker::Config.random = Random.new(PageCrawl::Browser::FAKER_SEED)
    travel_to(PageCrawl::Browser::CLOCK) { example.run }
  ensure
    Faker::Config.random = nil
  end

  before do
    stub_shopify_admin!
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
  end

  it "opens its views without new axe violations or SEVERE console errors" do
    shard_files = Rails.root.glob("#{PageCrawl::Browser::DIR}/shard_*_spec.rb")
    expect(shard_files.size).to eq(PageCrawl::Browser::SHARDS)

    world = PageCrawl::World.new(self)
    admin_pages = crawl_pages(world, sign_in: true)
    guest_pages = crawl_pages(world, sign_in: false).except(*admin_pages.keys)
    admin_pages.select! { |key, _| PageCrawl::Browser.shard_of(key) == shard }
    guest_pages.select! { |key, _| PageCrawl::Browser.shard_of(key) == shard }

    found = { axe: {}, errors: {} }
    crawl(guest_pages, found)
    log_in_as(admin)
    crawl(admin_pages, found)

    crawled = admin_pages.keys + guest_pages.keys
    expected = owned(YAML.safe_load_file(PageCrawl::Browser.templates_file), shard)
    known = YAML.safe_load_file(PageCrawl::Browser.baseline_file)
    baseline = known.slice(*owned(known.keys, shard))
    changes = PageCrawl::Browser.baseline_changes(found[:axe], baseline)
    write_report(shard, crawled, found[:axe]) if changes.any? || ENV["CRAWL_REPORT"]

    aggregate_failures do
      gone = expected - crawled
      expect(gone).to eq([]), "Views no longer crawled (the list only grows): #{gone.sort.join(', ')}"
      added = crawled - expected
      expect(added).to eq([]), "Newly crawled views, add them to templates.yml: #{added.sort.join(', ')}"
      expect(changes).to be_empty, <<~MSG
        The axe results differ from #{PageCrawl::Browser::DIR}/axe_baseline.yml:
        #{changes.join("\n")}
        New violations (fix them; the baseline only shrinks):
        #{new_violation_details(found[:axe], baseline).join("\n")}
        A count that went down is a fix: copy the lower counts from
        #{report_file(shard).relative_path_from(Rails.root)} into the baseline.
      MSG
      expect(found[:errors]).to eq({})
    end
  end
end
