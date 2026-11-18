# frozen_string_literal: true

require "rails_helper"

# /staff/unavailabilities: the staff member's own calendar of unavailabilities
# (the unavailabilities_calendar, unavailability_form and ics_links Stimulus
# controllers). The week shown
# is Sun 2027-03-14 .. Sat 2027-03-20.

RSpec.describe "Staff unavailabilities page", type: :system do
  include ActiveSupport::Testing::TimeHelpers
  include SpacesSpecHelpers

  let!(:space) { create(:space, name: "Calendar Lab") }
  let!(:staff) { create(:user, :staff, name: "Wanda Worker", space_id: space.id) }
  let(:eastern) { Time.zone }

  before { create(:staff_space, user: staff, space: space) }

  around { |ex| travel_to(Time.zone.local(2027, 3, 16, 12)) { ex.run } }

  def open_page
    log_in_as(staff, to: staff_unavailabilities_path, local_storage: { fullCalendarDefaultDateStaffUnavailabilities: CalendarJsHelpers::WEEK_MIDDAY })
    expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 14 – 20, 2027")
    page.execute_script("window.sameDocument = true")
  end

  # A dialog save closes the dialog and redraws the calendar in the same document.
  def expect_saved_in_place
    expect(page).to have_no_css("#unavailabilityModal.show")
    expect(page.evaluate_script("window.sameDocument")).to be(true)
  end

  def open_add_modal
    page.execute_script("document.getElementById('unavailabilityModal').addEventListener('shown.bs.modal', function (e) { e.target.dataset.shown = '1'; })")
    click_button "+ Add Unavailability"
    expect(page).to have_css("#unavailabilityModal[data-shown]")
  end

  def open_entry(title, index: 0)
    expect(page).to have_css(".fc-timegrid-event", text: title, visible: :all)
    page.all(".fc-timegrid-event", text: title, visible: :all)[index].click
    expect(page).to have_css("#unavailabilityModal.show")
  end

  def create_series
    create(:staff_unavailability, user: staff, title: "Class",
                                  start_time: eastern.local(2027, 3, 15, 10), end_time: eastern.local(2027, 3, 15, 11),
                                  recurrence_rule: "DTSTART:20270315T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20270331T235959Z")
  end

  describe "the calendar" do
    it "shows only the signed-in staff member's unavailabilities", js: true, skip_bullet: true do
      create(:staff_unavailability, user: staff, title: "Lecture",
                                    start_time: eastern.local(2027, 3, 17, 13), end_time: eastern.local(2027, 3, 17, 15))
      create(:staff_unavailability, user: create(:user, :staff), title: "Someone else",
                                    start_time: eastern.local(2027, 3, 17, 13), end_time: eastern.local(2027, 3, 17, 15))
      open_page

      expect(page).to have_css(".fc-timegrid-event", text: "Lecture", visible: :all)
      expect(page).to have_no_css(".fc-event", text: "Someone else", visible: :all)
      expect(page).to have_css("#spinner_container", visible: :hidden)
    end

    it "remembers the week shown", js: true, skip_bullet: true do
      open_page
      find(".fc-next-button").click
      expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 21 – 27, 2027")

      visit staff_unavailabilities_path
      expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 21 – 27, 2027")
    end

    it "opens the add dialog by dragging across the calendar", js: true, skip_bullet: true do
      open_page
      slot = find(".fc-timegrid-col[data-date='2027-03-17'] .fc-timegrid-col-frame", visible: :all)
      page.driver.browser.action.move_to(slot.native, 10, 300).click_and_hold.move_by(0, 80).release.perform

      expect(page).to have_css("#unavailabilityModal.show")
      expect(page).to have_css("#unavailabilityModalLabel", text: "Add Unavailability")
      expect(field_value("start_time_field")).to start_with("2027-03-17T")
      expect(field_value("end_time_field")).to start_with("2027-03-17T")
    end
  end

  describe "adding" do
    it "opens the modal in add mode", js: true, skip_bullet: true do
      open_page
      open_add_modal

      expect(page).to have_css("#unavailabilityModalLabel", text: "Add Unavailability")
      expect(find("#save_button").value).to eq("Save")
      expect(page).to have_css("#delete_forms", visible: :hidden)
      expect(page).to have_css("#update_dropdown", visible: :hidden)
    end

    it "saves an unavailability with the typed times and a default title", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      fill_datetime("end_time_field", "2027-03-17T12:00")
      click_button "Save"

      expect_flash("Unavailability created.")
      expect_saved_in_place
      expect(page).to have_css(".fc-timegrid-event", text: "Unavailable", visible: :all)
      saved = StaffUnavailability.find_by!(user: staff)
      expect(saved.title).to eq("Unavailable")
      expect(saved.start_time).to eq(toronto_utc("2027-03-17T10:00"))
      expect(saved.end_time).to eq(toronto_utc("2027-03-17T12:00"))
      expect(saved.recurrence_rule).to be_nil
    end

    it "saves the title and description it was given", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      fill_datetime("end_time_field", "2027-03-17T12:00")
      open_custom_values
      fill_in "title", with: "Dentist"
      fill_in "description", with: "Cleaning"
      click_button "Save"

      eventually { StaffUnavailability.exists?(user_id: staff.id) }
      expect(StaffUnavailability.find_by!(user: staff).attributes.values_at("title", "description")).to eq(%w[Dentist Cleaning])
    end

    it "refuses to save an end that is not after the start", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      fill_datetime("end_time_field", "2027-03-17T09:00")

      expect(page).to have_css("#time_error:not(.d-none)")
      expect(page).to have_css("#save_button[disabled]")
      fill_datetime("end_time_field", "2027-03-17T11:00")
      expect(page).to have_no_css("#save_button[disabled]")
    end

    it "makes an all-day unavailability span midnight to midnight", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      check "all_day_checkbox"

      expect(field_value("start_time_field")).to eq("2027-03-17T00:00")
      expect(field_value("end_time_field")).to eq("2027-03-18T00:00")
      expect(page).to have_field("end_time_field", disabled: true)
      click_button "Save"

      eventually { StaffUnavailability.exists?(user_id: staff.id) }
      saved = StaffUnavailability.find_by!(user: staff)
      expect(saved.start_time).to eq(toronto_utc("2027-03-17T00:00"))
      expect(saved.end_time).to eq(toronto_utc("2027-03-18T00:00"))
    end

    it "saves a weekly repeat on the ticked days up to the end date", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      fill_datetime("end_time_field", "2027-03-17T12:00")
      select "Weekly", from: "recurrence_frequency"
      expect(page).to have_checked_field("day_WE")
      check "day_FR"
      find("#recurrence_until").set(Date.new(2027, 4, 30))
      click_button "Save"

      eventually { StaffUnavailability.exists?(user_id: staff.id) }
      rule = StaffUnavailability.find_by!(user: staff).recurrence_rule
      expect(rule).to include("FREQ=WEEKLY")
      expect(rule).to match(/BYDAY=(WE,FR|FR,WE)/)
      expect(rule).to include("UNTIL=")
    end

    it "ticks only the weekday of the start for a weekly all-day entry, and follows a changed start date", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      select "Weekly", from: "recurrence_frequency"
      check "all_day_checkbox"
      expect(page).to have_checked_field("day_WE")
      fill_datetime("start_time_field", "2027-03-19T10:00")

      expect(field_value("start_time_field")).to eq("2027-03-19T00:00")
      expect(field_value("end_time_field")).to eq("2027-03-20T00:00")
      expect(page).to have_checked_field("day_FR")
      expect(page).to have_unchecked_field("day_WE")
    end

    it "offers daily and monthly repeats without the weekday boxes", js: true, skip_bullet: true do
      open_page
      open_add_modal
      select "Monthly", from: "recurrence_frequency"
      expect(page).to have_css("#recurrence_options", visible: :visible)
      expect(page).to have_css("#weekly_options", visible: :hidden)
      select "Does not repeat", from: "recurrence_frequency"
      expect(page).to have_css("#recurrence_options", visible: :hidden)
    end

    it "warns when a weekly repeat has no day ticked", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      select "Weekly", from: "recurrence_frequency"
      uncheck "day_WE"
      expect(page).to have_css("#day_freq_error:not(.d-none)")
      check "day_TU"
      expect(page).to have_css("#day_freq_error.d-none", visible: :all)
    end

    it "keeps the dialog open with what was typed and the alert when the server refuses the save", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      fill_datetime("end_time_field", "2027-03-17T12:00")
      open_custom_values
      fill_in "title", with: "Dentist"
      select "Weekly", from: "recurrence_frequency"
      uncheck "day_WE"
      click_button "Save"

      expect(page).to have_css("#unavailabilityModal.show #calendar_dialog_alert", text: "Failed to create unavailability")
      expect(page).to have_no_css("#flash", text: "Failed to create unavailability")
      expect(find("#title", visible: :all).value).to eq("Dentist")
      expect(field_value("start_time_field")).to eq("2027-03-17T10:00")
      expect(page).to have_select("recurrence_frequency", selected: "Weekly")
      expect(page.evaluate_script("window.sameDocument")).to be(true)
      expect(StaffUnavailability.count).to eq(0)

      accept_confirm { click_button "Cancel" }
      expect(page).to have_no_css("#unavailabilityModal.show")
      open_add_modal
      expect(page).to have_no_css("#calendar_dialog_alert .alert")
    end

    it "returns the focus to the add button when the dialog is closed", js: true, skip_bullet: true do
      open_page
      open_add_modal
      accept_confirm { page.send_keys(:escape) }
      expect(page).to have_no_css("#unavailabilityModal.show")
      expect(page).to have_css("#addUnavailabilityButton:focus")
    end

    it "asks before closing and resets the form when closed", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      select "Daily", from: "recurrence_frequency"
      dismiss_confirm("Are you sure you want to exit? All changes will be lost.") { click_button "Cancel" }
      expect(page).to have_css("#unavailabilityModal.show")

      accept_confirm { click_button "Cancel" }
      expect(page).to have_no_css("#unavailabilityModal.show")
      expect(page).to have_css("#recurrence_options", visible: :hidden)
      expect(StaffUnavailability.count).to eq(0)
    end
  end

  describe "with the browser clock in Tokyo", browser_zone: "Asia/Tokyo" do
    it "saves the typed times in Toronto time and shows them again", js: true, skip_bullet: true do
      open_page
      open_add_modal
      fill_datetime("start_time_field", "2027-03-17T10:00")
      fill_datetime("end_time_field", "2027-03-17T12:00")
      click_button "Save"

      eventually { StaffUnavailability.exists?(user_id: staff.id) }
      saved = StaffUnavailability.find_by!(user: staff)
      expect(saved.start_time).to eq(eastern.local(2027, 3, 17, 10))
      expect(saved.end_time).to eq(eastern.local(2027, 3, 17, 12))
      open_entry("Unavailable")
      expect(field_value("start_time_field")).to eq("2027-03-17T10:00")
      expect(field_value("end_time_field")).to eq("2027-03-17T12:00")
    end
  end

  describe "editing and deleting" do
    let!(:lecture) do
      create(:staff_unavailability, user: staff, title: "Lecture", description: "Calculus",
                                    start_time: eastern.local(2027, 3, 17, 13), end_time: eastern.local(2027, 3, 17, 15))
    end

    it "fills the modal from the entry", js: true, skip_bullet: true do
      open_page
      open_entry("Lecture")

      expect(page).to have_css("#unavailabilityModalLabel", text: "Edit Unavailability")
      expect(find("#save_button").value).to eq("Update")
      expect(find("#unavailForm", visible: :all)[:action]).to end_with("/staff/unavailabilities/#{lecture.id}")
      expect(find("#title", visible: :all).value).to eq("Lecture")
      expect(find("#description", visible: :all).value).to eq("Calculus")
      expect(field_value("start_time_field")).to eq(toronto_field(lecture.start_time))
      expect(field_value("end_time_field")).to eq(toronto_field(lecture.end_time))
      expect(page).to have_css("#delete_forms", visible: :visible)
      expect(page).to have_css("#delete_following_form", visible: :hidden)
    end

    it "saves a new title and times", js: true, skip_bullet: true do
      open_page
      open_entry("Lecture")
      open_custom_values
      fill_in "title", with: "Lab"
      fill_datetime("start_time_field", "2027-03-18T16:00")
      fill_datetime("end_time_field", "2027-03-18T17:00")
      click_button "Update"

      expect_flash("Unavailability updated successfully.")
      expect_saved_in_place
      expect(page).to have_css(".fc-timegrid-event", text: "Lab", visible: :all)
      lecture.reload
      expect(lecture.title).to eq("Lab")
      expect(lecture.start_time).to eq(toronto_utc("2027-03-18T16:00"))
    end

    it "deletes the entry", js: true, skip_bullet: true do
      open_page
      open_entry("Lecture")
      click_button "Delete"
      click_button "This event"

      expect_flash("Unavailability deleted.")
      expect_saved_in_place
      expect(page).to have_no_css(".fc-timegrid-event", text: "Lecture", visible: :all)
      expect(StaffUnavailability.exists?(lecture.id)).to be(false)
    end

    # The dialog's opening transition is held until the test ends it, so the
    # delete answers while the dialog is still opening.
    it "closes the dialog when the delete answers before it has finished opening", js: true, skip_bullet: true do
      open_page
      page.execute_script(<<~JS)
        const style = document.createElement("style");
        style.textContent = "#unavailabilityModal .modal-dialog { transition-duration: 600s !important; }";
        document.head.append(style);
      JS
      open_entry("Lecture")
      click_button "Delete"
      click_button "This event"
      expect_flash("Unavailability deleted.")

      page.execute_script("document.querySelector('#unavailabilityModal .modal-dialog').dispatchEvent(new Event('transitionend'))")
      expect_saved_in_place
    end

    it "keeps all-day entries locked to whole days when opened", js: true, skip_bullet: true do
      lecture.update!(title: "Away", start_time: eastern.local(2027, 3, 17, 0), end_time: eastern.local(2027, 3, 18, 0))
      open_page
      expect(page).to have_css(".fc-daygrid-event", text: "Away", visible: :all)
      find(".fc-daygrid-event", text: "Away", visible: :all).click

      expect(page).to have_checked_field("all_day_checkbox")
      expect(page).to have_field("end_time_field", disabled: true)
    end
  end

  describe "a repeating entry" do
    it "restores the repeat settings and offers the scope menu and the three delete choices", js: true, skip_bullet: true do
      create_series
      open_page
      open_entry("Class", index: 1)

      expect(find("#recurrence_frequency", visible: :all).value).to eq("WEEKLY")
      expect(page).to have_checked_field("day_MO", visible: :all)
      expect(page).to have_checked_field("day_WE", visible: :all)
      expect(field_value("recurrence_until")).to eq("2027-03-31")
      expect(page).to have_css("#update_dropdown_items #save_button", visible: :all)
      click_button "Delete"
      expect(page).to have_button("This and following events")
      expect(page).to have_button("All events")
    end

    it "updates only the clicked occurrence by default", js: true, skip_bullet: true do
      series = create_series
      open_page
      open_entry("Class", index: 1)
      open_custom_values
      fill_in "title", with: "Class (moved)"
      find("#update_dropdown > button").click
      click_button "Update"

      eventually { StaffUnavailability.where(title: "Class (moved)").exists? }
      expect(StaffUnavailability.where(title: "Class (moved)", recurrence_rule: nil).count).to eq(1)
      expect(series.reload.recurrence_rule).to include("EXDATE")
    end

    it "updates the whole series with 'Update all events'", js: true, skip_bullet: true do
      series = create_series
      open_page
      open_entry("Class", index: 1)
      open_custom_values
      fill_in "title", with: "Class (renamed)"
      find("#update_dropdown > button").click
      choose "update_all"
      click_button "Update"

      eventually { series.reload.title == "Class (renamed)" }
      expect(series.reload.title).to eq("Class (renamed)")
    end

    it "excludes the occurrence instant for 'This event'", js: true, browser_zone: "America/Toronto", skip_bullet: true do
      series = create_series
      open_page
      open_entry("Class", index: 1)
      click_button "Delete"
      click_button "This event"

      eventually { series.reload.recurrence_rule.include?("EXDATE") }
      expect(series.reload.recurrence_rule).to include("EXDATE:20270317T140000Z")
      # The form submit reloads the page; the Wednesday occurrence is gone and Monday remains.
      expect(page).to have_css(".fc-timegrid-event", text: "Class", count: 1, visible: :all)
      expect(page).to have_css(".fc-day-mon .fc-timegrid-event", text: "Class", visible: :all)
      expect(page).to have_no_css(".fc-day-wed .fc-timegrid-event", text: "Class", visible: :all)
    end

    it "ends the series with 'This and following events'", js: true, browser_zone: "America/Toronto", skip_bullet: true do
      series = create_series
      open_page
      open_entry("Class", index: 1)
      click_button "Delete"
      click_button "This and following events"

      eventually { series.reload.recurrence_rule.include?("UNTIL=20270316T140000Z") }
      expect(series.reload.recurrence_rule).to include("UNTIL=20270316T140000Z")
    end

    describe "with the browser clock in Tokyo", browser_zone: "Asia/Tokyo" do
      it "shows the repeat end date and removes one occurrence by its own instant", js: true, skip_bullet: true do
        series = create_series
        open_page
        open_entry("Class", index: 1)
        expect(field_value("start_time_field")).to eq("2027-03-17T10:00")
        expect(field_value("recurrence_until")).to eq("2027-03-31")
        click_button "Delete"
        click_button "This event"

        eventually { series.reload.recurrence_rule.include?("EXDATE") }
        expect(series.reload.recurrence_rule).to include("EXDATE:20270317T140000Z")
      end
    end

    it "deletes the series with 'All events'", js: true, skip_bullet: true do
      series = create_series
      open_page
      open_entry("Class", index: 1)
      click_button "Delete"
      click_button "All events"

      eventually { !StaffUnavailability.exists?(series.id) }
      expect(StaffUnavailability.exists?(series.id)).to be(false)
    end
  end

  describe "imported calendar links" do
    before do
      allow(IcsFetcher).to receive(:get).and_return(nil)
    end

    it "adds an empty link field each time New Calendar is pressed", js: true, skip_bullet: true do
      open_page
      expect(page).to have_css("#link-container input", count: 0)
      click_button "New Calendar"
      click_button "New Calendar"

      expect(page).to have_css("#link-container input[name='external_calendar[]']", count: 2)
      expect(page).to have_css("#link-container input[name='external_calendar[]']:not([id])", count: 2)
    end

    it "removes a link field with its delete button", js: true, skip_bullet: true do
      create(:staff_external_unavailability, user: staff, ics_url: "https://feeds.example.org/a.ics")
      open_page
      expect(page).to have_field(with: "https://feeds.example.org/a.ics")
      find("#link-container .calendar-delete-button").click

      expect(page).to have_no_field(with: "https://feeds.example.org/a.ics")
    end

    it "saves the links that are left", js: true, skip_bullet: true do
      create(:staff_external_unavailability, user: staff, ics_url: "https://feeds.example.org/a.ics")
      open_page
      click_button "New Calendar"
      within("#link-container") { all("input").last.set("https://feeds.example.org/b.ics") }
      click_button "Save Calendars"

      eventually { StaffExternalUnavailability.where(user: staff).count == 2 }
      expect(StaffExternalUnavailability.where(user: staff).pluck(:ics_url))
        .to contain_exactly("https://feeds.example.org/a.ics", "https://feeds.example.org/b.ics")
    end

    it "refuses a link that is not http or https and changes nothing", js: true, skip_bullet: true do
      create(:staff_external_unavailability, user: staff, ics_url: "https://feeds.example.org/a.ics")
      open_page
      click_button "New Calendar"
      within("#link-container") { all("input").last.set("ftp://feeds.example.org/b.ics") }
      click_button "Save Calendars"

      expect(page).to have_current_path(staff_unavailabilities_path)
      expect(page).to have_css("#link-container input", count: 1)
      expect(StaffExternalUnavailability.where(user: staff).pluck(:ics_url)).to eq(["https://feeds.example.org/a.ics"])
    end
  end

  describe "an event imported from a linked calendar" do
    let(:feed_url) { "https://feeds.example.org/private/secret-token/dentist.ics" }

    before do
      create(:staff_external_unavailability, user: staff, ics_url: feed_url)
      body = ics_document(uid: "feed-1", summary: "Dentist", description: "Bring the forms",
                          start: Time.utc(2027, 3, 17, 17), end: Time.utc(2027, 3, 17, 19))
      allow(IcsFetcher).to receive(:get).and_return(nil)
      allow(IcsFetcher).to receive(:get).with(feed_url, any_args).and_return(body)
    end

    it "opens a read-only dialog that explains it cannot be changed here", js: true, skip_bullet: true do
      open_page
      expect(page).to have_css(".fc-timegrid-event", text: "External - Dentist", visible: :all)
      page.execute_script("document.getElementById('importedEventModal').addEventListener('shown.bs.modal', function (e) { e.target.dataset.shown = '1'; })")
      page.all(".fc-timegrid-event", text: "External - Dentist", visible: :all).first.click
      expect(page).to have_css("#importedEventModal.show[data-shown]")

      within("#importedEventModal.show") do
        expect(page).to have_css("#importedEventModalLabel", text: "External - Dentist")
        expect(page).to have_text("1:00")
        expect(page).to have_text("Bring the forms")
        expect(page).to have_text("Imported from a linked calendar (feeds.example.org)")
        expect(page).to have_no_text("secret-token")
        expect(page).to have_text("can't be edited or deleted here")
        expect(page).to have_no_button("Save")
        expect(page).to have_no_button("Update")
        expect(page).to have_no_button("Delete")
        click_button "Close"
      end
      expect(page).to have_no_css("#importedEventModal.show")
      expect(page).to have_no_css("#unavailabilityModal.show")
    end
  end

  describe "a linked calendar that cannot be loaded" do
    it "names its host without showing the link", js: true, skip_bullet: true do
      url = "https://down.example.org/private/secret-token/basic.ics"
      create(:staff_external_unavailability, user: staff, ics_url: url)
      allow(IcsFetcher).to receive(:get).and_return(nil)
      open_page

      expect(page).to have_css("[data-unavailabilities-calendar-target='failures']", text: "down.example.org could not be loaded")
      expect(page).to have_no_text("secret-token")
    end

    it "shows no message when the linked calendars load", js: true, skip_bullet: true do
      create(:staff_external_unavailability, user: staff, ics_url: "https://fine.example.org/a.ics")
      allow(IcsFetcher).to receive(:get).and_return(ics_document)
      open_page

      expect(page).to have_css(".fc-timegrid", visible: :all)
      expect(page).to have_no_text("could not be loaded")
    end
  end

  describe "a series that ends on a day" do
    # Daily at 1:00 until Wednesday 2027-03-17: the stored end is the last
    # second of that Toronto day (04:00 UTC on the Thursday).
    it "shows no occurrence after its last day", js: true, skip_bullet: true do
      create(:staff_unavailability, user: staff, title: "Night shift",
                                    start_time: eastern.local(2027, 3, 15, 1), end_time: eastern.local(2027, 3, 15, 2),
                                    recurrence_rule: "DTSTART:20270315T050000Z\nRRULE:FREQ=DAILY;UNTIL=20270318T035959Z")
      open_page

      expect(page).to have_css(".fc-timegrid-event", text: "Night shift", visible: :all, count: 3)
    end
  end
end
