# frozen_string_literal: true

require "rails_helper"

# Collapsible section headers open and close their panel from the header button
# or from the rest of the header, and aria-expanded on the button follows the panel.
RSpec.describe "Accordion headers", type: :system do
  let!(:admin) { create(:user, :admin) }
  let(:world) { PageCrawl::World.new(self) }

  before do
    stub_shopify_admin!
    log_in_as(admin)
  end

  def route_for(spec)
    PageCrawl.routes.find { |r| r.path_spec == spec } || raise("no GET route #{spec}")
  end

  def visit_page(spec)
    visit PageCrawl.fill(route_for(spec), world).first
    wait_for_page_settled
  end

  # Clicks the header near its left edge, away from the centred button text.
  def click_header_edge(header)
    width = header.evaluate_script("this.getBoundingClientRect().width")
    header.click(x: -(width / 2).to_i + 4, y: 0)
  end

  shared_examples "an accordion" do
    it "toggles from the button and from the rest of the header" do
      expect(page).to have_css("#{header_css} button[aria-expanded]", minimum: 1)
      header = first(header_css)
      button = header.find("button")
      target = panel_css(button)
      panel = find(target, visible: :all)
      expect(button["aria-expanded"]).to eq("false")

      button.click
      expect(page).to have_css(target, visible: :visible)
      expect(page).to have_no_css(".collapsing")
      expect(button["aria-expanded"]).to eq("true")
      expect(header[:"aria-expanded"]).to be_nil
      button.click
      expect(page).to have_no_css(target, visible: :visible)
      expect(page).to have_no_css(".collapsing")
      expect(button["aria-expanded"]).to eq("false")

      click_header_edge(header)
      expect(page).to have_css(target, visible: :visible)
      expect(page).to have_no_css(".collapsing")
      expect(panel).to be_present
      click_header_edge(header)
      expect(page).to have_no_css(target, visible: :visible)
      expect(page).to have_no_css(".collapsing")

      # an open panel stays open, with its button marked expanded, after a reload
      button.click
      expect(page).to have_css(target, visible: :visible)
      expect(page).to have_no_css(".collapsing")
      page.refresh
      wait_for_page_settled
      expect(page).to have_css(target, visible: :visible)
      expect(first(header_css).find("button")["aria-expanded"]).to eq("true")
    end
  end

  describe "university programs" do
    let(:header_css) { ".card-header" }

    before { visit_page("/admin/uni_programs") }

    def panel_css(button) = button["data-bs-target"]

    it_behaves_like "an accordion"
  end

  describe "proficient projects" do
    let(:header_css) { ".card-header" }

    before do
      PageCrawl.fill(route_for("/proficient_projects/:id/edit"), world)
      visit_page("/proficient_projects")
    end

    def panel_css(button) = button["data-bs-target"]

    it_behaves_like "an accordion"
  end

  describe "admin menu" do
    it "lists its links without bullets or extra spacing" do
      visit "/admin"
      wait_for_page_settled
      style = page.evaluate_script(<<~JS)
        (() => {
          const ul = document.querySelector("ul.list-group");
          const li = ul.querySelector("li");
          return [getComputedStyle(li).listStyleType, getComputedStyle(ul).paddingLeft,
                  getComputedStyle(ul).marginBottom, getComputedStyle(li).marginLeft];
        })();
      JS
      expect(style).to eq(%w[none 0px 0px 0px])
    end
  end
end
