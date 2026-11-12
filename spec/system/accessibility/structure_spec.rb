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
    /labs /explore /getting-started/setting-up-account /getting-started/creating-repository /admin /admin/users
    /admin/uni_programs /development_programs /proficient_projects /volunteers/my_stats
    /project_proposals/new /admin/keys/:key_id/revoke
    ]
  end

  let!(:admin) { create(:user, :admin) }

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

      visit path
      wait_for_page_settled
      AxeAudit.record(AxeAudit.run(page, only: rules), spec, nil).map { |v| "#{spec} #{v.rule} #{v.selector}" }
    end

    expect(violations.join("\n")).to eq("")
  end
end
