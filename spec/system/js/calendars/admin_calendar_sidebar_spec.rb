# frozen_string_literal: true

require "rails_helper"

# The sidebar and toolbar of the admin calendar (fullcalendar_setup_admin.js,
# calendar.js): staff, event-type and imported-calendar checkboxes, the hours
# badges, the toolbar toggles, the draft buttons, copy week and staff colours.

RSpec.describe "Admin calendar: sidebar and toolbar", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space, name: "Calendar Lab") }
  let!(:admin) { create(:user, :admin, name: "Ada Admin", space_id: space.id) }
  let!(:worker) { create(:user, :staff, name: "Wanda Worker", space_id: space.id) }
  let(:eastern) { Time.zone }

  before do
    create(:staff_space, user: admin, space: space)
    create(:staff_space, user: worker, space: space, color: "#cc3300")
  end

  around { |ex| travel_to(Time.zone.local(2027, 3, 16, 12)) { ex.run } }

  def open_admin_calendar(query = "")
    log_in_as(admin)
    visit root_path
    page.execute_script("localStorage.fullCalendarDefaultDateAdmin = '#{CalendarJsHelpers::WEEK_MIDDAY}'")
    visit "#{admin_calendar_index_path}#{query}"
    expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 14 – 20, 2027")
    wait_for_admin_calendar_scripts
  end

  def event_titled(title)
    page.all(".fc-timegrid-event", text: title, visible: :all)
  end

  def query_params
    Rack::Utils.parse_query(URI.parse(page.current_url).query.to_s)
  end

  describe "staff checkboxes" do
    let!(:lecture) do
      create(:staff_unavailability, user: worker, title: "Lecture",
                                    start_time: eastern.local(2027, 3, 17, 13), end_time: eastern.local(2027, 3, 17, 15))
    end

    it "lists every staff member of the space with an All Staff checkbox", js: true, skip_bullet: true do
      open_admin_calendar

      expect(page).to have_checked_field("checkbox-#{worker.id}", visible: :all)
      expect(page).to have_checked_field("checkbox-#{admin.id}", visible: :all)
      expect(page).to have_checked_field("checkbox-all", visible: :all)
      expect(page).to have_css("label", text: "Wanda Worker")
      expect(page).to have_css("label", text: "All Staff")
      expect(page).to have_css(".fc-timegrid-event", text: "Lecture", visible: :all)
    end

    it "hides one staff member's unavailabilities and records it in the address", js: true, skip_bullet: true do
      open_admin_calendar
      expect(event_titled("Lecture").size).to eq(1)

      uncheck "checkbox-#{worker.id}", allow_label_click: true

      expect(page).to have_no_css(".fc-timegrid-event", text: "Lecture", visible: :all)
      expect(query_params["hidden_staff"]).to eq(worker.id.to_s)
      check "checkbox-#{worker.id}", allow_label_click: true
      expect(page).to have_css(".fc-timegrid-event", text: "Lecture", visible: :all)
      expect(query_params).not_to have_key("hidden_staff")
    end

    it "unticks All Staff when one member is hidden, and All Staff hides everyone", js: true, skip_bullet: true do
      open_admin_calendar
      uncheck "checkbox-#{worker.id}", allow_label_click: true
      expect(page).to have_unchecked_field(class: "all_checkbox", visible: :all)

      find("input.all_checkbox", visible: :all).check(allow_label_click: true)
      expect(page).to have_checked_field("checkbox-#{worker.id}", visible: :all)
      find("input.all_checkbox", visible: :all).uncheck(allow_label_click: true)
      expect(page).to have_unchecked_field("checkbox-#{worker.id}", visible: :all)
      expect(page).to have_unchecked_field("checkbox-#{admin.id}", visible: :all)
      expect(page).to have_no_css(".fc-timegrid-event", text: "Lecture", visible: :all)
      expect(query_params["hidden_staff"].split(",")).to contain_exactly(worker.id.to_s, admin.id.to_s)
    end

    it "starts with a staff member hidden when the address lists them", js: true, skip_bullet: true do
      open_admin_calendar("?hidden_staff=#{worker.id}")

      expect(page).to have_unchecked_field("checkbox-#{worker.id}", visible: :all)
      expect(page).to have_unchecked_field(class: "all_checkbox", visible: :all)
      expect(page).to have_no_css(".fc-timegrid-event", text: "Lecture", visible: :all)
    end

    it "marks a staff member without unavailabilities with a placeholder source", js: true, skip_bullet: true do
      open_admin_calendar

      expect(page).to have_css("label", text: "Ada Admin")
      expect(page).to have_no_css(".fc-event", text: "No Unavailabilities", visible: :all)
    end
  end

  describe "staff event checkboxes" do
    let!(:shift) do
      create(:event, space: space, title: "Front desk", event_type: "shift", draft: false,
                     start_time: eastern.local(2027, 3, 17, 9), end_time: eastern.local(2027, 3, 17, 12))
    end

    before { create(:event_assignment, event: shift, user: worker) }

    it "shows each staff member's hours in the view next to their name", js: true, skip_bullet: true do
      open_admin_calendar

      expect(page).to have_css("#checkbox-#{worker.id} ~ .user-hours, .user-hours", text: "3 hrs", wait: 10)
      row = find("#checkbox-#{worker.id}").ancestor("div.d-flex")
      expect(row).to have_css(".user-hours", text: "3 hrs")
      expect(find("#checkbox-#{admin.id}").ancestor("div.d-flex")).to have_css(".user-hours", text: "0 hrs")
    end

    it "hides the events assigned to a staff member with the slash checkbox", js: true, skip_bullet: true do
      open_admin_calendar
      expect(event_titled("Front desk").size).to eq(1)

      uncheck "checkbox-events-#{worker.id}", allow_label_click: true

      expect(page).to have_no_css(".fc-timegrid-event", text: "Front desk", visible: :all)
      expect(query_params["hidden_staff_events"]).to eq(worker.id.to_s)
      check "checkbox-events-#{worker.id}", allow_label_click: true
      expect(page).to have_css(".fc-timegrid-event", text: "Front desk", visible: :all)
    end

    it "unticks that staff member's events checkbox when the address lists them, but still draws the events", js: true, skip_bullet: true do
      open_admin_calendar("?hidden_staff_events=#{worker.id}")

      expect(page).to have_unchecked_field("checkbox-events-#{worker.id}", visible: :all)
      # the events are fetched before the address is read, so they are still drawn
      expect(page).to have_css(".fc-timegrid-event", text: "Front desk", visible: :all)
    end

    it "hides the events of everyone with the first slash checkbox", js: true, skip_bullet: true do
      open_admin_calendar
      find("input.all_events_checkbox", visible: :all).uncheck(allow_label_click: true)

      expect(page).to have_unchecked_field("checkbox-events-#{worker.id}", visible: :all)
      expect(page).to have_no_css(".fc-timegrid-event", text: "Front desk", visible: :all)
    end
  end

  describe "imported calendars" do
    it "says so when the space has none", js: true, skip_bullet: true do
      open_admin_calendar

      expect(page).to have_css("#imported_calendars_status", text: "No calendars found")
    end

    it "lists each one with a checkbox that shows and hides its events", js: true, skip_bullet: true do
      url = "https://feeds.example.org/classes.ics"
      calendar = StaffNeededCalendar.create!(calendar_url: url, name: "Class timetable", color: "#228833")
      calendar.update!(space_id: space.id)
      allow(IcsFetcher).to receive(:get).with(url, any_args)
        .and_return(ics_feed(uid: "cls-1", summary: "Circuits class",
                             starts: Time.utc(2027, 3, 17, 15), ends: Time.utc(2027, 3, 17, 16)))
      open_admin_calendar

      expect(page).to have_css(".fc-timegrid-event", text: "Circuits class", visible: :all)
      expect(page).to have_css("#imported_calendars_status", visible: :hidden)
      expect(page).to have_css("#calendars_checkbox_container label", text: "Class timetable")
      box = find("#calendars_checkbox_container input[type=checkbox]")
      box.uncheck(allow_label_click: true)

      expect(page).to have_no_css(".fc-timegrid-event", text: "Circuits class", visible: :all)
      expect(query_params["hidden_calendars"]).to eq(box.value)
      box.check(allow_label_click: true)
      expect(page).to have_css(".fc-timegrid-event", text: "Circuits class", visible: :all)
    end

    it "starts with a calendar hidden when the address lists it", js: true, skip_bullet: true do
      url = "https://feeds.example.org/classes.ics"
      StaffNeededCalendar.create!(calendar_url: url, name: "Class timetable", space_id: space.id)
      allow(IcsFetcher).to receive(:get).with(url, any_args)
        .and_return(ics_feed(uid: "cls-1", summary: "Circuits class",
                             starts: Time.utc(2027, 3, 17, 15), ends: Time.utc(2027, 3, 17, 16)))
      group_id = Digest::MD5.hexdigest(url)
      open_admin_calendar("?hidden_calendars=#{group_id}")

      expect(page).to have_unchecked_field("checkbox-#{group_id}", visible: :all)
      expect(page).to have_no_css(".fc-timegrid-event", text: "Circuits class", visible: :all)
    end
  end

  describe "toolbar toggles" do
    it "hides and shows the weekend columns", js: true, skip_bullet: true do
      open_admin_calendar

      expect(page).to have_css(".fc-toggleWeekends-button", text: "Hide Weekends")
      expect(page).to have_css("th.fc-col-header-cell[data-date]", count: 7)
      find(".fc-toggleWeekends-button").click
      expect(page).to have_css("th.fc-col-header-cell[data-date]", count: 5)
      expect(page).to have_css(".fc-toggleWeekends-button", text: "Show Weekends")
      find(".fc-toggleWeekends-button").click
      expect(page).to have_css("th.fc-col-header-cell[data-date]", count: 7)
    end

    it "remembers the event overlap setting in the browser", js: true, skip_bullet: true do
      open_admin_calendar

      expect(page).to have_css(".fc-toggleEventOverlap-button", text: "Enable Event Overlap")
      find(".fc-toggleEventOverlap-button").click
      expect(page).to have_css(".fc-toggleEventOverlap-button", text: "Disable Event Overlap")
      expect(page.evaluate_script("localStorage.fullCalendarEventOverlap")).to eq("true")
      visit admin_calendar_index_path
      expect(page).to have_css(".fc-toggleEventOverlap-button", text: "Disable Event Overlap")
    end

    it "remembers the week shown when the page is reloaded", js: true, skip_bullet: true do
      open_admin_calendar
      find(".fc-next-button").click

      expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 21 – 27, 2027")
      visit admin_calendar_index_path
      expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 21 – 27, 2027")
    end

    it "names the draft buttons after the week or the month", js: true, skip_bullet: true do
      open_admin_calendar

      expect(page).to have_button("publish_drafts_button", exact: false, text: "Publish This Week's Drafts")
      expect(page).to have_css("#delete_drafts_button", text: "Delete This Week's Drafts")
      find(".fc-dayGridMonth-button").click
      expect(page).to have_css("#publish_drafts_button", text: "Publish This Month's Drafts")
      expect(page).to have_css("#delete_drafts_button", text: "Delete This Month's Drafts")
    end
  end

  describe "drafts" do
    let!(:draft) do
      create(:event, :draft, space: space, title: "Draft talk", event_type: "meeting",
                             start_time: eastern.local(2027, 3, 17, 10), end_time: eastern.local(2027, 3, 17, 11))
    end
    let!(:outside) do
      create(:event, :draft, space: space, title: "Later draft", event_type: "meeting",
                             start_time: eastern.local(2027, 4, 20, 10), end_time: eastern.local(2027, 4, 20, 11))
    end

    it "publishes the drafts of the week shown and no others", js: true, skip_bullet: true do
      open_admin_calendar
      find("#publish_drafts_button").click
      click_button "Confirm Publish"

      expect(page).to have_text("1 event(s) published.")
      expect(draft.reload.draft).to be(false)
      expect(outside.reload.draft).to be(true)
    end

    it "deletes the drafts of the week shown and no others", js: true, skip_bullet: true do
      open_admin_calendar
      find("#delete_drafts_button").click
      click_button "Confirm Delete"

      expect(page).to have_text("1 draft event(s) deleted.")
      expect(Event.exists?(draft.id)).to be(false)
      expect(Event.exists?(outside.id)).to be(true)
    end

    it "sends the first and last day of the view with both buttons", js: true, skip_bullet: true do
      open_admin_calendar

      starts = page.all(".view_start_date", visible: :all).map(&:value).uniq
      ends = page.all(".view_end_date", visible: :all).map(&:value).uniq
      expect(starts).to eq(["2027-03-14T00:00:00"])
      expect(ends).to eq(["2027-03-21T00:00:00"])
    end
  end

  describe "copying a week" do
    it "copies the published events of the source range onto the target week as drafts", js: true, skip_bullet: true do
      create(:event, space: space, title: "Open lab", event_type: "other", draft: false,
                     start_time: eastern.local(2027, 3, 16, 10), end_time: eastern.local(2027, 3, 16, 11))
      open_admin_calendar
      click_button "Copy Events"
      expect(page).to have_css("#copyEventsModal.show")
      page.execute_script(<<~JS)
        document.getElementById("source_range")._flatpickr.setDate(["2027-03-14", "2027-03-20"], true);
        document.getElementById("target_date")._flatpickr.setDate("2027-03-28", true);
      JS
      within("#copyEventsModal") { click_button "Copy Events" }

      expect(page).to have_text("1 published event(s) copied to 2027-03-28.")
      copy = Event.where(title: "Open lab", draft: true).first
      expect(copy.start_time).to eq(eastern.local(2027, 3, 30, 10))
    end

    it "asks for both fields before copying", js: true, skip_bullet: true do
      open_admin_calendar
      click_button "Copy Events"
      expect(page).to have_css("#copyEventsModal.show")
      within("#copyEventsModal") { click_button "Copy Events" }

      expect(page).to have_text("Please fill out all fields before copying.")
    end

    # Closing the dialog throws "flatpickr is not a function" from its hide handler; the dialog still closes.
    it "closes the copy dialog with Cancel", js: true, skip_bullet: true do
      open_admin_calendar
      page.execute_script("document.getElementById('copyEventsModal').addEventListener('shown.bs.modal', function (e) { e.target.dataset.shown = '1'; })")
      click_button "Copy Events"
      # a dialog still fading in ignores a close request
      expect(page).to have_css("#copyEventsModal[data-shown]")
      within("#copyEventsModal") { click_button "Cancel" }

      expect(page).to have_no_css("#copyEventsModal.show")
    end
  end

  describe "staff colours" do
    it "saves a colour picked for a staff member", js: true, skip_bullet: true do
      open_admin_calendar
      page.execute_script(<<~JS)
        var input = document.getElementById("color-#{worker.id}");
        input.value = "#112233";
        input.dispatchEvent(new Event("change", { bubbles: true }));
      JS

      expect(page).to have_css("#color-#{worker.id}")
      eventually { StaffSpace.find_by(user: worker, space: space).color == "#112233" }
      expect(StaffSpace.find_by(user: worker, space: space).color).to eq("#112233")
    end

    it "reloads the calendar with the Refresh Calendar button", js: true, skip_bullet: true do
      open_admin_calendar
      page.execute_script("document.getElementById('calendar').dataset.marker = '1'")
      click_button "Refresh Calendar"

      expect(page).to have_css("#calendar:not([data-marker]) .fc-toolbar-title", text: "Mar 14 – 20, 2027")
    end
  end
end
