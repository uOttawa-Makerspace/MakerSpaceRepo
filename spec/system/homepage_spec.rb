# frozen_string_literal: true

require "rails_helper"

# DOM-level characterization of the homepage chrome: navbar, featured tiles
# (hours, explore, makerstore, workshops, newsletter) and the footer, as a
# guest and as a signed-in user. Simpli.events and Shopify are stubbed at the
# HTTP boundary (spec/support/webmock.rb defaults, overridden below for the
# populated case).
#
# JS console: the page boots FullCalendar (fullcalendar_setup_homepage) which
# fetches /open_hours; the JS-error check is being added to system specs by a
# parallel chunk, so no SEVERE console errors were observed or asserted here
# (see c17-notes.md).
# N+1 pinned: see defects D-PERF-P03 (home eager-loads variant_records it never uses)
RSpec.describe "Homepage", type: :system, skip_bullet: true do
  let(:workshop_ms) { (Time.current + 3.days).to_i * 1000 }

  before do
    stub_request(:get, %r{\Ahttps://simpli\.events/api/organizer/}).to_return(
      status: 200,
      body: { events: [{ "name" => "Intro to Soldering", "startTime" => workshop_ms,
                         "link" => "https://simpli.events/e/solder", "picture" => "" }] }.to_json
    )
    stub_request(:post, %r{\Ahttps://[^/]+\.myshopify\.com/admin/api/}).with(body: /collections\(first: 8\)/).to_return(
      status: 200,
      body: { data: { collections: { nodes: [
        { "id" => "1", "handle" => "filament", "title" => "Filament", "description" => "",
          # inline 1x1 PNG: the hermetic test browser resolves only localhost
          "image" => { "url" => "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" } }
      ] } } }.to_json
    )
    create(:repository, title: "Featured Gizmo")
    create(:announcement, :all, description: "Maker night this Friday")
  end

  def expect_public_chrome
    # Navbar
    expect(page).to have_css("nav.navbar.navbar-expand-xl")
    expect(page).to have_css("a.navbar-brand", text: "MakerRepo")
    within("nav.navbar") do
      expect(page).to have_css("a.nav-link", text: "Home", visible: :all)
      expect(page).to have_css("a.nav-link", text: "FAQ", visible: :all)
      expect(page).to have_css("a.dropdown-item[href='/explore']", visible: :all)
      expect(page).to have_css("a.dropdown-item[href='#{get_involved_path}']", visible: :all)
      expect(page).to have_css("a.dropdown-item[href='#{resources_path}']", visible: :all)
    end

    # Announcement banner
    expect(page).to have_css(".alert", text: "Maker night this Friday")

    # Featured tiles
    expect(page).to have_css("section#home")
    expect(page).to have_css("#home-hours", text: /welcome/i)
    expect(page).to have_css("#home-hours a.fc-button[href='#{hours_path}']")
    expect(page).to have_css("#exploreCarousel .card-title", text: "Featured Gizmo")
    expect(page).to have_css("#storeCarousel a[href='https://makerstore.ca/collections/filament']", text: "Filament")
    expect(page).to have_css("#storeCarousel a[href='https://makerstore.ca']", text: "Makerstore")
    expect(page).to have_css(".workshop-card .workshop-title", text: "Intro to Soldering")
    expect(page).to have_css("#home-big-newsletter a.btn", text: /sign up|subscribe/i)

    # Footer
    expect(page).to have_css("footer")
    within("footer") do
      expect(page).to have_link(href: contact_path)
      expect(page).to have_link(href: help_path)
      expect(page).to have_link(href: tos_path)
      expect(page).to have_link(href: about_path)
      expect(page).to have_css("img[alt='CEED Logo']")
      expect(page).to have_text(Time.zone.now.year.to_s)
    end
  end

  it "shows the public chrome and tiles to a guest, with a sign-in entry and no user cards" do
    visit root_path
    expect_public_chrome
    expect(page).to have_css("a.nav-link", text: /sign in/i, visible: :all)
    expect(page).to have_no_css("#home-user-info")
    expect(page).to have_no_text("Staff Resources")
  end

  it "shows the same tiles plus the user chip to a signed-in regular user" do
    user = create(:user, :regular_user)
    log_in_as(user)
    visit root_path
    expect_public_chrome
    expect(page).to have_css("nav.navbar", text: user.username)
    expect(page).to have_css("#home-hours", text: user.name)
    expect(page).to have_no_css("a.nav-link", text: /sign in/i, visible: :all)
    expect(page).to have_no_link(href: admin_settings_path)
  end

  it "still renders every tile when both integrations are down" do
    stub_request(:get, %r{\Ahttps://simpli\.events/api/organizer/}).to_return(status: 500)
    stub_request(:post, %r{\Ahttps://[^/]+\.myshopify\.com/admin/api/}).with(body: /collections\(first: 8\)/).to_timeout
    visit root_path
    expect(page).to have_css("section#home")
    expect(page).to have_css("#exploreCarousel .card-title", text: "Featured Gizmo")
    expect(page).to have_css("#storeCarousel a[href='https://makerstore.ca']")
    expect(page).to have_no_css(".workshop-card")
    expect(page).to have_no_css("#storeCarousel a[href*='/collections/']")
    expect(page).to have_css("footer")
  end

  it "shows staff links to staff but not the admin settings link" do
    staff = create(:user, :staff)
    log_in_as(staff)
    visit root_path
    expect(page).to have_link(href: staff_dashboard_index_path)
    expect(page).to have_no_link(href: admin_settings_path)
  end
end
