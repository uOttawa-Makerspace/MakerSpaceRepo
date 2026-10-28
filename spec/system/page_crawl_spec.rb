# frozen_string_literal: true

require "rails_helper"

# Browser crawl (admin) over the pages that load a page-specific JS entrypoint
# (anything besides the shared "application" bundle). A Rack probe first picks
# the admin-visible HTML pages whose markup includes such an entrypoint, then
# each is opened in headless Chrome and must log no SEVERE console error
# outside spec/support/js_error_allowlist.rb. The no-500 breadth check for all
# roles lives in spec/requests/page_crawl_spec.rb.
RSpec.describe "Page crawl (browser, JS entrypoints)", type: :system, skip_bullet: true do
  ENTRYPOINT = %r{/vite-test/assets/(?!application-)[\w.-]+\.js}

  let!(:admin) { create(:user, :admin) }

  before do
    stub_shopify_admin!
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
  end

  def js_pages(world)
    probe = ActionDispatch::Integration::Session.new(Rails.application)
    probe.post login_authentication_path, params: { username_email: admin.username, password: PageCrawl::PASSWORD }
    PageCrawl.routes.filter_map do |route|
      next if PageCrawl.skip_reason(route)

      path, = PageCrawl.fill(route, world)
      next unless path

      probe.get path
      next unless probe.response.status == 200 && probe.response.media_type == "text/html"

      entries = probe.response.body.scan(ENTRYPOINT).uniq.sort
      [path, entries] unless entries.empty?
    end
  end

  # Keep at most PER_SIGNATURE pages for each distinct set of entrypoints: the
  # bundles (not the record ids) decide which JS runs.
  PER_SIGNATURE = 1

  def sample(pages_with_entries)
    pages_with_entries.group_by(&:last).values.flat_map { |g| g.first(PER_SIGNATURE).map(&:first) }
  end

  it "opens every admin-visible page with a JS entrypoint without SEVERE console errors" do
    world = PageCrawl::World.new(self)
    if (pending, approved, declined = world.records[:booking_statuses])
      stub_const("BookingStatus::PENDING", pending)
      stub_const("BookingStatus::APPROVED", approved)
      stub_const("BookingStatus::DECLINED", declined)
    end
    all_pages = js_pages(world)
    pages = sample(all_pages)
    expect(all_pages.size).to be > 100 # guard: the probe really found the JS pages
    expect(pages.size).to be > 20

    log_in_as(admin)
    problems = {}
    pages.each do |path|
      visit path
      expect(page).to have_css("body")
      # let page scripts finish: Turbo + deferred modules mark the document loaded
      expect(page).to have_css("nav.navbar, body")
      errors = JsErrorCheck.collect(page)
      problems[path] = errors.map { |e| e[:message] } if errors.any?
    end
    File.write(Rails.root.join("tmp/page_crawl_browser.json"), JSON.pretty_generate(pages: pages, problems: problems)) if ENV["CRAWL_REPORT"]
    puts "BROWSER CRAWL: #{pages.size} of #{all_pages.size} pages" if ENV["CRAWL_REPORT"]
    expect(problems).to eq({})
  end
end
