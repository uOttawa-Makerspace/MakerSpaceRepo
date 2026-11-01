# frozen_string_literal: true

require "rails_helper"

# Role-based GET crawl (request level, breadth). Every GET route (see
# spec/support/page_crawl.rb for what is excluded) is visited as guest,
# regular user, staff and admin against a seeded "world" and must not answer
# 500. Routes that currently 500 are pinned in KNOWN_500 (route + role ->
# reason); an entry that stops failing, or a new 500, fails the example so
# the table is always exact. Routes the world cannot fill are skipped and
# listed (set CRAWL_REPORT=1 to dump coverage to tmp/page_crawl_report.json).
RSpec.describe "Page crawl (request level)", type: :request, skip_bullet: true do
  # route (path spec) => { role => short reason }
  ALL = PageCrawl::ROLES
  KNOWN_500 = {
    "/memberships" => ALL.index_with { "no_tier_row" }, # no day-pass membership tier row in the world
    "/printers/last_user_assigned_to_printer" => %i[staff admin].index_with { "printer_without_session" },
    "/staff/my_calendar" => %i[staff admin].index_with { "my_calendar_500" },
    "/staff_dashboard/refresh_tables" => %i[staff admin].index_with { "refresh_tables_500" },
    "/admin/uni_programs/current_programs" => { admin: "current_programs_500" }
  }.freeze

  PERSONAS = {
    regular: [:user, :regular_user],
    staff: [:user, :staff],
    admin: [:user, :admin]
  }.freeze

  def log_in_persona(role)
    return if role == :guest

    user = create(*PERSONAS.fetch(role))
    post login_authentication_path, params: { username_email: user.username, password: PageCrawl::PASSWORD }
    expect(response).to redirect_to(root_path)
  end

  def crawl(role)
    stub_shopify_admin!
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
    world = PageCrawl::World.new(self)
    if (pending, approved, declined = world.records[:booking_statuses])
      stub_const("BookingStatus::PENDING", pending)
      stub_const("BookingStatus::APPROVED", approved)
      stub_const("BookingStatus::DECLINED", declined)
    end
    log_in_persona(role)
    visited = {}
    skipped = {}
    errors = {}
    PageCrawl.routes.each do |route|
      if (why = PageCrawl.skip_reason(route))
        skipped[route.path_spec] = why
        next
      end
      path, why = PageCrawl.fill(route, world)
      if path.nil?
        skipped[route.path_spec] = why
        next
      end
      visited[route.path_spec] = begin
        get path
        errors[route.path_spec] = error_summary if response.status == 500
        response.status
      rescue StandardError => e
        errors[route.path_spec] = "raised #{e.class}: #{e.message.lines.first}"
        "raised #{e.class}"
      end
    end
    @errors = errors
    [visited, skipped, world]
  end

  # Exception class and message from the Rails debug page
  def error_summary
    body = response.body.to_s
    strip = ->(t) { CGI.unescapeHTML(t.to_s.gsub(/<[^>]+>/, " ")).squish }
    head = strip.call(body[%r{<h1>(.*?)</h1>}m, 1])
    msg = strip.call(body[%r{class="exception-message">(.*?)</div>\s*</div>}m, 1])
    msg = strip.call(body[%r{<main.*?</main>}m]).first(300) if msg.blank?
    "#{head} #{msg}".squish.first(400)
  end

  def dump_report(role, visited, skipped, world)
    return unless ENV["CRAWL_REPORT"]

    dir = Rails.root.join("tmp")
    File.write(dir.join("page_crawl_#{role}.json"),
               JSON.pretty_generate(visited: visited, skipped: skipped, world_failures: world.failures, errors: @errors))
  end

  PageCrawl::ROLES.each do |role|
    it "no GET route answers 500 as #{role} (beyond the pinned table)" do
      visited, skipped, world = crawl(role)
      dump_report(role, visited, skipped, world)

      expect(visited.size).to be > 150 # guard: the crawl really visited the app

      failing = visited.select { |_, s| s == 500 || s.is_a?(String) }.keys
      pinned = KNOWN_500.select { |_, roles| roles.key?(role) }.keys
      expect(failing - pinned).to eq([]), "new 500s as #{role}: #{(failing - pinned).inspect}"
      expect(pinned - failing).to eq([]), "pinned 500s no longer failing as #{role}: #{(pinned - failing).inspect}"
    end
  end
end
