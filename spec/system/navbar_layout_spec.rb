# frozen_string_literal: true

require "rails_helper"

# The main navbar is orange in the light theme and its links are 14pt bold white
# (large text). It expands from 1200px. Up to 1600px it uses tighter padding and
# shows the theme, language, username and CC items as icons, with their labels
# kept for screen readers, so the longest link set (a signed-in admin with a long
# username, in French) fits on one line.
RSpec.describe "Main navbar layout", type: :system, skip_bullet: true do
  let(:admin) { create(:user, :admin, username: "W" * 19) }

  before do
    stub_request(:get, %r{\Ahttps://simpli\.events/api/organizer/}).to_return(status: 200, body: { events: [] }.to_json)
  end

  def sign_in_admin
    log_in_as(admin, to: root_path)
    use_light_theme
  end

  def use_light_theme
    page.driver.browser.manage.add_cookie(name: "theme", value: "light")
  end

  def open_at(width, locale:)
    page.driver.browser.manage.window.resize_to(width, 900)
    visit "/?locale=#{locale}"
    expect(page).to have_css("nav.navbar a.navbar-brand")
  end

  def navbar_layout
    page.evaluate_script(<<~JS)
      (function () {
        var nav = document.querySelector("nav.navbar");
        var bar = nav.querySelector(".container-fluid");
        var links = Array.from(nav.querySelectorAll(".navbar-collapse .nav-link")).filter(function (l) { return l.offsetParent; });
        var middles = links.map(function (l) { var r = l.getBoundingClientRect(); return r.top + r.height / 2; });
        var lowest = Math.min.apply(null, links.map(function (l) { return l.getBoundingClientRect().height; }));
        return {
          overflows: bar.scrollWidth > bar.clientWidth || document.documentElement.scrollWidth > window.innerWidth,
          oneLine: Math.max.apply(null, middles) - Math.min.apply(null, middles) < lowest / 2,
          links: links.length,
          size: links.length ? getComputedStyle(links[0]).fontSize : null
        };
      })()
    JS
  end

  def expect_one_row(min_links)
    expect(page).to have_no_css("#navbar-toggle-button", visible: :visible)
    result = navbar_layout
    expect(result).to include("overflows" => false, "oneLine" => true, "size" => "18.672px")
    expect(result["links"]).to be >= min_links
  end

  [1200, 1366, 1440, 1600, 1920].each do |width|
    %w[en fr].each do |locale|
      it "shows every link of a signed-in admin on one line at #{width}px in #{locale}" do
        sign_in_admin
        open_at(width, locale:)
        expect_one_row(11)
      end
    end
  end

  %w[en fr].each do |locale|
    it "shows every link of a guest on one line at 1200px in #{locale}" do
      visit root_path
      use_light_theme
      open_at(1200, locale:)
      expect_one_row(10)
    end
  end

  it "keeps the theme, language, username and CC labels for screen readers at 1366px" do
    sign_in_admin
    open_at(1366, locale: "fr")
    within("nav.navbar") do
      expect(page).to have_css("#themeToggler[aria-label='Thème']")
      expect(page).to have_css(".navbar-compact-label", text: "Thème", visible: :all)
      expect(page).to have_css("button .navbar-compact-label", text: "English", visible: :all)
      expect(page).to have_css(".navbar-compact-label", text: admin.username, visible: :all)
      expect(page).to have_css(".ccLink .navbar-compact-label", text: admin.get_total_cc.to_s, visible: :all)
    end
    expect(page.evaluate_script("getComputedStyle(document.querySelector('#themeToggler .navbar-compact-label')).position")).to eq("absolute")
  end

  [1199, 400].each do |width|
    it "uses the collapsed menu at #{width}px, with the large text size and full labels" do
      sign_in_admin
      open_at(width, locale: "fr")
      expect(page).to have_css("#navbar-toggle-button", visible: :visible)
      expect(navbar_layout["links"]).to eq(0)
      find("#navbar-toggle-button").click
      expect(page).to have_css("#navbarSupportedContent .nav-link", text: /Accueil/i, visible: :visible)
      expect(page).to have_css("#navbarSupportedContent button.nav-link", text: /English/i, visible: :visible)
      expect(navbar_layout).to include("size" => "18.672px")
    end
  end

  it "keeps the sign-in link on the collapsed bar for a guest at 400px" do
    open_at(400, locale: "en")
    expect(page).to have_css("#navbar-toggle-button", visible: :visible)
    expect(page).to have_css("nav.navbar > .container-fluid > a.nav-link", text: /Sign in/i, visible: :visible)
  end

  [1200, 1400, 1920].each do |width|
    it "passes the accessibility audit in the light theme at #{width}px" do
      sign_in_admin
      open_at(width, locale: "fr")
      expect(page.evaluate_script("document.documentElement.dataset.bsTheme")).to eq("light")
      audit_accessibility("light theme navbar #{width}px")
    end
  end
end
