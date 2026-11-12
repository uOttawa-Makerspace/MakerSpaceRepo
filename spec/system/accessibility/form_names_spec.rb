# frozen_string_literal: true

require "rails_helper"

# Every form control has an accessible name: axe's `label` and `select-name`
# rules report nothing. Pages are the ones the full-site axe crawl found failing,
# opened as the admin.
RSpec.describe "Form controls are named", type: :system do
  let(:rules) { %w[label select-name] }

  let(:pages) do
    %w[
    /videos/new /project_kits/new /project_proposals/new /project_proposals/:id/edit /locker_rentals/:id
    /admin/announcements/new /admin/announcements/:id/edit /admin/users/search /admin/trainings/new
    /admin/trainings/:id/edit /admin/contact_infos/new /admin/contact_infos/:id/edit /admin/settings
    /admin/keys/:key_id/revoke /admin/keys/new /admin/keys/:id/edit /admin/key_transactions/:id/edit
    /admin/teams/new /admin/teams/:id/edit /admin/teams/:id /admin/uni_programs /learning_area/new
    /learning_area/:id/edit /volunteers/my_stats
    ]
  end

  let!(:admin) { create(:user, :admin) }
  let(:queries) { { "/admin/users/search" => "?q=#{admin.username}&filter=Username" } }

  before do
    stub_shopify_admin!
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
  end

  def route_for(spec)
    PageCrawl.routes.find { |r| r.path_spec == spec } || raise("no GET route #{spec}")
  end

  def expect_search_results
    expect(page).to have_css("input[name='bulk_cert_users[]'][aria-label]")
    expect(page).to have_css("#select-all[aria-label]")
  end

  it "names every control on the audited pages" do
    world = PageCrawl::World.new(self)
    log_in_as(admin)

    violations = pages.flat_map do |spec|
      path, why = PageCrawl.fill(route_for(spec), world)
      raise "cannot fill #{spec}: #{why}" unless path

      visit "#{path}#{queries[spec]}"
      wait_for_page_settled
      expect(page).to have_current_path(path, ignore_query: true)
      expect(page).to have_css("input, select, textarea", visible: :all)
      expect_search_results if spec == "/admin/users/search"
      AxeAudit.record(AxeAudit.run(page, only: rules), spec, nil).map { |v| "#{spec} #{v.rule} #{v.selector}" }
    end

    expect(violations.join("\n")).to eq("")
  end
end
