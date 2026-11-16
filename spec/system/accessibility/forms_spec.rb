# frozen_string_literal: true

require "rails_helper"

# Every form control on these pages has an accessible name: axe's `label`,
# `select-name`, `aria-input-field-name` and `button-name` rules report nothing.
# Pages are the ones the full-site axe crawl found failing, opened as the admin.
RSpec.describe "Form controls have accessible names", type: :system do
  let(:rules) { %w[label select-name aria-input-field-name button-name] }

  let(:pages) do
    %w[
    /videos/new /project_kits/new /project_proposals/new /project_proposals/:id/edit
    /printer_issues/new /printer_issues/:id/edit /locker_rentals/:id /faq/new /faq/:id/edit /help
    /admin/announcements/new /admin/announcements/:id/edit /admin/job_types/new /admin/job_types/:id/edit
    /admin/users/search /admin/trainings/new /admin/trainings/:id/edit
    /admin/contact_infos/new /admin/contact_infos/:id/edit /admin/settings
    /admin/keys/:key_id/revoke /admin/keys/new /admin/keys/:id/edit /admin/key_transactions/:id/edit
    /admin/teams/new /admin/teams/:id/edit /admin/teams/:id /admin/uni_programs
    /proficient_projects/:id/edit /learning_area/new /learning_area/:id/edit /volunteers/my_stats
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

  it "names every form control on the audited pages" do
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
