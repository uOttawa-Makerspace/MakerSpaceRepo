# frozen_string_literal: true

require "rails_helper"

# Role-based GET crawl (request level, breadth). Every GET route (see
# spec/support/page_crawl.rb for what is excluded) is visited as guest,
# regular user, staff and admin against a seeded "world" and must not answer
# 500. Routes that currently 500 are pinned in KNOWN_500 (route + role ->
# reason); an entry that stops failing, or a new 500, fails the example so
# the table is always exact. Routes the world cannot fill are skipped and
# listed (set CRAWL_REPORT=1 to dump coverage to tmp/page_crawl_report.json).
# The crawl runs on one fixed clock (the same instant the browser crawl uses),
# so the world's records and the request params (calendar week, staff
# conflicts slot) are the same whatever the real date.
RSpec.describe "Page crawl (request level)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # Same fixed time as the browser crawl (noon in Toronto), so both crawls see the same dates.
  around { |example| travel_to(PageCrawl::Browser::CLOCK) { example.run } }

  # route (path spec) => { role => short reason }
  ALL = PageCrawl::ROLES
  KNOWN_500 = {}.freeze

  PERSONAS = {
    regular: [:user, :regular_user],
    staff: [:user, :staff],
    admin: [:user, :admin]
  }.freeze

  def log_in_persona(role, world)
    return if role == :guest

    user = create(*PERSONAS.fetch(role))
    create(:staff_space, user: user, space: world.records[:space]) unless role == :regular
    post login_authentication_path, params: { username_email: user.username, password: PageCrawl::PASSWORD }
    expect(response).to redirect_to(root_path)
  end

  def crawl(role)
    stub_shopify_admin!
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
    world = PageCrawl::World.new(self)

    log_in_persona(role, world)
    visited = {}
    skipped = {}
    errors = {}
    @routes_by_path = {}
    @locations = {}
    PageCrawl.routes.each do |route|
      @routes_by_path[route.path_spec] = route
      if (why = PageCrawl.skip_reason(route))
        skipped[route.path_spec] = why
        next
      end
      path, why = PageCrawl.fill(route, world)
      if path.nil?
        skipped[route.path_spec] = why
        next
      end
      visited[route.path_spec] = visit(route, path, world, errors)
    end
    @errors = errors
    [visited, skipped, world]
  end

  # The answer's status; records a redirect's target and any error for the route
  def visit(route, path, world, errors)
    request_page(route, path, world)
    errors[route.path_spec] = error_summary if response.status == 500
    @locations[route.path_spec] = URI(response.location).path if response.redirect?
    response.status
  rescue StandardError => e
    errors[route.path_spec] = "raised #{e.class}: #{e.message.lines.first}"
    "raised #{e.class}"
  end

  def request_page(route, path, world)
    options = PageCrawl::RequestOptions.for(route, world)
    path += ".#{options.delete(:format)}" if options.key?(:format)
    get path, **options
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

  def acceptable?(path, role, status, answer)
    status.is_a?(Integer) && status != 500 && PageCrawl::Expectations.acceptable?(path, role, answer)
  end

  def answer_for(path, visited)
    [visited[path], @locations[path]]
  end

  # Route, status and the exception (if any) for each failing route
  def failure_details(paths, visited)
    paths.map { |p| "#{p} -> #{visited[p]}#{" #{@locations[p]}" if @locations[p]}#{" (#{@errors[p]})" if @errors[p]}" }.join("; ")
  end

  def dump_report(role, visited, skipped, world)
    return unless ENV["CRAWL_REPORT"]

    dir = Rails.root.join("tmp")
    File.write(dir.join("page_crawl_#{role}.json"),
               JSON.pretty_generate(visited: visited, skipped: skipped, world_failures: world.failures, errors: @errors, locations: @locations))
  end

  PageCrawl::ROLES.each do |role|
    it "no GET route answers 500 as #{role} (beyond the pinned table)" do
      visited, skipped, world = crawl(role)
      dump_report(role, visited, skipped, world)

      expect(visited.size).to be > 150 # guard: the crawl really visited the app

      answers = visited.to_h { |path, _| [path, answer_for(path, visited)] }
      failing = visited.reject { |path, s| acceptable?(path, role, s, answers[path]) }.keys
      pinned = KNOWN_500.select { |_, roles| roles.key?(role) }.keys
      expect(failing - pinned).to eq([]), "unexpected answers as #{role}: #{failure_details(failing - pinned, visited)}"
      stale = PageCrawl::Expectations.stale_entries(answers, role).map { |e, off| "#{e[:path].source}: #{off.join(', ')}" }
      expect(stale).to eq([]), "expected-answer entries that no longer hold as #{role}: #{stale.inspect}"
      expect(pinned - failing).to eq([]), "pinned 500s no longer failing as #{role}: #{(pinned - failing).inspect}"
    end
  end
end
