# frozen_string_literal: true

require "rails_helper"

# Which booking tab opens on each way of reaching the page, and how a tab click
# shows its pane. Bootstrap's tab plugin handles every click. On the page the
# browser loaded in full, the page script also shows the clicked pane at once,
# so it appears without Bootstrap's fade; on a page Turbo rendered later in the
# same document the pane fades in.
RSpec.describe "Sub-space booking: tabs", :booking_clock, type: :system do
  before do
    create(:booking_status, :pending)
    create(:booking_status, :approved)
    create(:booking_status, :rejected)
  end

  let(:space) { create(:space, name: "Maker Hall") }
  let(:subspace) { create(:sub_space, space: space, name: "Laser Room") }
  let(:admin) { create(:user, :admin, name: "Ada Admin", booking_approval: true) }
  let(:booking_path) { sub_space_booking_index_path(room: subspace.id) }

  def turbo_visit(path)
    page.execute_script("Turbo.visit(arguments[0])", path)
  end

  def expect_open(tab)
    expect(page).to have_css("##{tab}.active.show", visible: :all)
    expect(page).to have_css(".tab-pane.active", count: 1, visible: :all)
    expect(page).to have_css("##{tab}-btn.active")
    expect(page).to have_css("#booking-tab-list .nav-link.active", count: 1)
  end

  # The class list of My Bookings' pane straight after its button is clicked,
  # before any transition has run.
  def pane_classes_on_click
    page.evaluate_script(<<~JS)
      (() => {
        document.getElementById("booking-tab-btn").click();
        return document.getElementById("booking-tab").className;
      })()
    JS
  end

  def expect_click_shows_at_once
    expect(pane_classes_on_click.split).to include("active", "show")
    expect_open("booking-tab")
    expect(page).to have_css("#booking-tab-btn[aria-selected='true']")
  end

  def expect_click_fades_in
    classes = pane_classes_on_click.split
    expect(classes).to include("active", "fade")
    expect(classes).not_to include("show")
    expect_open("booking-tab")
    expect(page).to have_css("#booking-tab-btn[aria-selected='true']")
  end

  describe "on a full page load", js: true, skip_bullet: true do
    it "opens Book Room and shows a clicked tab at once" do
      log_in_as(admin, to: booking_path)
      expect_open("booking-calendar-tab")
      expect_click_shows_at_once
    end

    it "opens the tab of the anchor, which wins over a page parameter" do
      log_in_as(admin, to: "#{booking_path}&approved_page=1#booking-tab")
      expect_open("booking-tab")
    end

    it "opens the admin tab for a page parameter" do
      log_in_as(admin, to: "#{booking_path}&denied_page=1")
      expect_open("booking-admin-tab")
    end

    it "opens Book Room for an anchor that names no tab" do
      log_in_as(admin, to: "#{booking_path}#nowhere")
      expect_open("booking-calendar-tab")
    end
  end

  describe "on a page Turbo renders later in the same document", js: true, skip_bullet: true do
    before do
      log_in_as(admin, to: booking_path)
      expect_open("booking-calendar-tab")
    end

    it "opens the tab the new address names and fades a clicked tab in" do
      turbo_visit("#{booking_path}&pending_page=1")
      expect(page).to have_current_path(/pending_page=1/)
      expect_open("booking-admin-tab")
      expect_click_fades_in
    end

    it "opens the tab of a new anchor" do
      turbo_visit("#{booking_path}&old_denied_page=1#booking-tab")
      expect(page).to have_current_path(/old_denied_page=1/)
      expect_open("booking-tab")
    end

    it "opens the tab the address names on Back and Forward, not the tab left open" do
      find("#booking-tab-btn").click
      expect_open("booking-tab")
      turbo_visit("#{booking_path}&pending_page=1")
      expect(page).to have_current_path(/pending_page=1/)
      expect_open("booking-admin-tab")
      find("#booking-calendar-tab-btn").click
      expect_open("booking-calendar-tab")

      page.go_back
      expect(page).to have_no_current_path(/pending_page/)
      expect_open("booking-calendar-tab")
      expect_click_fades_in

      page.go_forward
      expect(page).to have_current_path(/pending_page=1/)
      expect_open("booking-admin-tab")
    end
  end
end
