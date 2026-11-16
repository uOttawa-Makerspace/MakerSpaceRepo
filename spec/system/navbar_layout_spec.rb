# frozen_string_literal: true

require "rails_helper"

# The main navbar is orange in the light theme and its links are 14pt bold white
# (large text). A signed-in admin reading French has the longest link set, about
# 1560px wide, so the bar expands from 1600px and shows the collapsed menu below.
RSpec.describe "Main navbar layout", type: :system, skip_bullet: true do
  let(:admin) { create(:user, :admin) }

  before do
    stub_request(:get, %r{\Ahttps://simpli\.events/api/organizer/}).to_return(status: 200, body: { events: [] }.to_json)
    log_in_as(admin, to: root_path)
    page.driver.browser.manage.add_cookie(name: "theme", value: "light")
  end

  def open_at(width, locale: "fr")
    page.driver.browser.manage.window.resize_to(width, 900)
    visit "/?locale=#{locale}"
    expect(page).to have_css("nav.navbar.navbar-expand-xxxl")
  end

  def navbar_overflow
    page.evaluate_script(<<~JS)
      (function () {
        var nav = document.querySelector("nav.navbar");
        var links = Array.from(nav.querySelectorAll(".navbar-collapse .nav-link")).filter(function (l) { return l.offsetParent; });
        return {
          scrolls: nav.scrollWidth > nav.clientWidth,
          wraps: nav.getBoundingClientRect().height > 80,
          links: links.length,
          size: links.length ? getComputedStyle(links[0]).fontSize : null
        };
      })()
    JS
  end

  it "shows every link in one row at 1600px, at the large text size" do
    open_at(1600)
    result = navbar_overflow
    expect(result).to include("scrolls" => false, "wraps" => false, "size" => "18.672px")
    expect(result["links"]).to be >= 10
    expect(page).to have_no_css("#navbar-toggle-button", visible: :visible)
  end

  it "uses the collapsed menu below 1600px, with the large text size" do
    open_at(1599)
    expect(page).to have_css("#navbar-toggle-button", visible: :visible)
    expect(navbar_overflow["links"]).to eq(0)
    find("#navbar-toggle-button").click
    expect(page).to have_css("#navbarSupportedContent .nav-link", text: /Accueil/i, visible: :visible)
    expect(navbar_overflow).to include("size" => "18.672px")
  end

  [1200, 1400, 1920].each do |width|
    it "passes the accessibility audit in the light theme at #{width}px" do
      open_at(width)
      expect(page.evaluate_script("document.documentElement.dataset.bsTheme")).to eq("light")
      find("#navbar-toggle-button").click if page.has_css?("#navbar-toggle-button", visible: :visible)
      audit_accessibility("light theme navbar #{width}px")
    end
  end
end
