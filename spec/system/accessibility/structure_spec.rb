# frozen_string_literal: true

require "rails_helper"

# Images have alternative text, links and buttons have names, lists and
# definition lists contain only their allowed children, progress bars are named
# and ARIA attributes sit on elements that support them: axe's `image-alt`,
# `link-name`, `button-name`, `list`, `listitem`, `definition-list`,
# `aria-progressbar-name` and `aria-allowed-attr` rules report nothing.
# Pages are the ones the full-site axe crawl found failing, opened as the admin.
RSpec.describe "Page structure is accessible", type: :system do
  let(:rules) do
    %w[image-alt link-name button-name list listitem definition-list aria-progressbar-name aria-allowed-attr]
  end

  let(:pages) do
    %w[
    /job_orders/:job_order_id/invoice /job_orders/landing /locker_rentals /memberships /terms_of_service /get_involved
    /labs /explore /search /getting-started/setting-up-account /getting-started/creating-repository /admin /admin/users
    /admin/users/search /admin/uni_programs /development_programs /proficient_projects /volunteers/my_stats
    /project_proposals/new /admin/keys/:key_id/revoke
    ]
  end

  let!(:admin) { create(:user, :admin) }
  # one repository card with a photo and one without, listed by /explore and /search
  let!(:photo_repository) { create(:repository, title: "Card with photo") }
  let!(:plain_repository) do
    build(:repository, title: "Card without photo").tap do |repo|
      repo.photos.clear
      repo.save!(validate: false)
    end
  end
  let(:queries) { { "/admin/users/search" => "?q=#{admin.username}&filter=Username" } }

  before do
    stub_shopify_admin!
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
  end

  def route_for(spec)
    PageCrawl.routes.find { |r| r.path_spec == spec } || raise("no GET route #{spec}")
  end

  it "passes the structure rules on the audited pages" do
    world = PageCrawl::World.new(self)
    log_in_as(admin)

    violations = pages.flat_map do |spec|
      path, why = PageCrawl.fill(route_for(spec), world)
      raise "cannot fill #{spec}: #{why}" unless path

      visit "#{path}#{queries[spec]}"
      wait_for_page_settled
      expect(page).to have_css("a.card-img-top img[alt='Card with photo']") if spec == "/explore"
      expect(page).to have_css("a.card-img-top img[alt='Card without photo']") if spec == "/explore"
      expect(page).to have_css("td.link-table a[aria-label]") if spec == "/admin/users/search"
      AxeAudit.record(AxeAudit.run(page, only: rules), spec, nil).map { |v| "#{spec} #{v.rule} #{v.selector}" }
    end

    expect(violations.join("\n")).to eq("")
  end

  it "indents the terms paragraphs like the numbered lists" do
    visit "/terms_of_service"
    wait_for_page_settled
    padding = ->(css) { page.evaluate_script("getComputedStyle(document.querySelector(#{css.to_json})).paddingLeft") }
    expect(padding.call("div.terms")).to eq(padding.call("ol.terms"))
    expect(padding.call("ol.terms")).not_to eq("0px")
  end
end
