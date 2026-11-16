# frozen_string_literal: true

require "rails_helper"

# Every <label for> and aria-labelledby on these pages points at an element that
# exists, and axe's `label` rule reports nothing. Pages are the ones where a
# label named an id that no control carried; they are opened as the admin.
RSpec.describe "Labels point at their controls", type: :system do
  let(:pages) do
    %w[
    /proficient_projects/new /proficient_projects/:id/edit /learning_area/new /learning_area/:id/edit
    /admin/job_types/new /admin/job_options/new /admin/job_services/new /admin/job_service_groups/new
    /admin/uni_programs /admin/add_new_staff /printers /job_orders/:id /key_requests/new
    /staff/unavailabilities /volunteers/new_event /volunteer_tasks/new /volunteer_tasks/:id/edit
    /volunteer_hours/new /volunteer_hours/:id/edit /announcements/new /announcements/:id/edit
    /:username /:user_username/new /:user_username/:id/edit /:user_username/:id
    /makes/:user_username/:id/new /project_proposals/new /project_proposals/:id/edit /admin/job_types/:id/edit /admin/settings
    ]
  end

  # Pages where an unrelated control (named by another slice) still fails axe's label rule.
  # The profile page's tab panes name tab buttons that are not rendered for every role (a separate defect).
  let(:labelledby_exempt) { %w[/:username] }
  let(:axe_exempt) { %w[/admin/uni_programs /volunteer_tasks/:id/edit] }

  # ids named by the given attribute selector that no element carries, as "tag attribute=id" strings
  def dangling(selector, attribute)
    page.evaluate_script(<<~JS)
      (() => Array.from(document.querySelectorAll(#{selector.to_json})).flatMap((el) =>
        el.getAttribute(#{attribute.to_json}).split(/\\s+/).filter((id) => id && !document.getElementById(id))
          .map((id) => `${el.tagName.toLowerCase()} #{attribute}=${id}`)))();
    JS
  end

  let!(:admin) { create(:user, :admin) }

  before do
    stub_shopify_admin!
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
  end

  def route_for(spec)
    PageCrawl.routes.find { |r| r.path_spec == spec } || raise("no GET route #{spec}")
  end

  def label_violations
    Axe::Configuration.instance.legacy_mode = true
    run = Axe::API::Run.new.excluding(*AxeAudit::EXCLUDED).checking_only("label")
    Axe::Core.new(page).call(run).results.violations.flat_map { |v| v.nodes.map { |n| n.target.join(" ") } }
  end

  it "resolves every label and passes the axe label rule" do
    world = PageCrawl::World.new(self)
    log_in_as(admin)

    problems = pages.flat_map do |spec|
      path, why = PageCrawl.fill(route_for(spec), world)
      raise "cannot fill #{spec}: #{why}" unless path

      visit path
      wait_for_page_settled
      refs = dangling("label[for]", "for").map { |r| "#{spec} #{r}" }
      refs += dangling("[aria-labelledby]", "aria-labelledby").map { |r| "#{spec} #{r}" } unless labelledby_exempt.include?(spec)
      axe = axe_exempt.include?(spec) ? [] : label_violations.map { |selector| "#{spec} axe label #{selector}" }
      refs + axe
    end

    expect(problems.join("\n")).to eq("")
  end

  it "leaves the settings create-course label pointing at its field" do
    world = PageCrawl::World.new(self)
    log_in_as(admin)
    visit PageCrawl.fill(route_for("/admin/settings"), world).first
    wait_for_page_settled
    expect(page).to have_css("label[for=create_course_name]", text: "Create course", visible: :all)
    expect(page).to have_css("input#create_course_name", visible: :all)
  end

  it "names each university program section by its heading" do
    world = PageCrawl::World.new(self)
    log_in_as(admin)
    visit PageCrawl.fill(route_for("/admin/uni_programs"), world).first
    wait_for_page_settled
    expect(page).to have_css("[aria-labelledby]", visible: :all)
    expect(dangling("[aria-labelledby]", "aria-labelledby")).to eq([])
  end
end
