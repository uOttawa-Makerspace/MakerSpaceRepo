# frozen_string_literal: true

require "rails_helper"

# The "Add Event" modal of the admin calendar (calendar_helper.js
# addEventClick / eventCreate, manage_calendar_events.js). The week shown is
# Sun 2027-03-14 .. Sat 2027-03-20. The browser reads and writes the modal's
# datetime-local fields in its own time zone, so expected instants are computed
# by the browser (browser_utc), not assumed.

RSpec.describe "Admin calendar: creating events", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space, name: "Calendar Lab") }
  let!(:admin) { create(:user, :admin, name: "Ada Admin", space_id: space.id) }
  let!(:worker) { create(:user, :staff, name: "Wanda Worker", space_id: space.id) }

  before do
    create(:staff_space, user: admin, space: space)
    create(:staff_space, user: worker, space: space, color: "#cc3300")
  end

  around { |ex| travel_to(Time.zone.local(2027, 3, 16, 12)) { ex.run } }

  def open_admin_calendar
    log_in_as(admin)
    show_week_of_march_14("fullCalendarDefaultDateAdmin", admin_calendar_index_path)
    expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 14 – 20, 2027")
    wait_for_admin_calendar_scripts
  end

  def open_add_modal
    page.execute_script("document.getElementById('eventModal').addEventListener('shown.bs.modal', function (e) { e.target.dataset.shown = '1'; })")
    click_button "+ Add Event"
    # shown (not just opening): a modal still fading in ignores a close request
    expect(page).to have_css("#eventModal[data-shown]")
  end

  def confirm_modal_hidden
    expect(page).to have_no_css("#eventModal.show")
  end

  it "opens the add modal with a draft save button, one-hour default times and no type chosen", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal

    expect(page).to have_css("#eventModalLabel", text: "Add Event")
    expect(find("#save_button").value).to eq("Save Draft")
    expect(find("#event_type_select").value).to eq("")
    start_ms = page.evaluate_script("new Date(document.getElementById('start_time_field').value).getTime()")
    end_ms = page.evaluate_script("new Date(document.getElementById('end_time_field').value).getTime()")
    expect(end_ms - start_ms).to eq(3_600_000)
    expect(page).to have_css("#time_error.d-none", visible: :all)
    expect(page).to have_css("#publish_and_delete_forms", visible: :hidden)
  end

  it "saves a draft event with the typed times, the chosen type and the assigned staff member", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:00")
    fill_datetime("end_time_field", "2027-03-17T11:30")
    select "Meeting", from: "event_type_select"
    find("#staff_select + .ts-wrapper .ts-control").click
    find(".ts-dropdown .option", text: "Wanda Worker").click
    find("#title", visible: :all).execute_script("this.value = 'Planning chat'")
    click_button "Save Draft"

    expect(page).to have_text("Event created successfully.")
    event = Event.find_by!(title: "Planning chat")
    expect(event.event_type).to eq("meeting")
    expect(event.draft).to be(true)
    expect(event.space_id).to eq(space.id)
    expect(event.start_time).to eq(browser_utc("2027-03-17T10:00"))
    expect(event.end_time).to eq(browser_utc("2027-03-17T11:30"))
    expect(event.recurrence_rule).to be_nil
    expect(event.users).to contain_exactly(worker)
  end

  it "titles an event after its type when the title is left blank", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-18T09:00")
    fill_datetime("end_time_field", "2027-03-18T10:00")
    select "Other", from: "event_type_select"
    click_button "Save Draft"

    expect(page).to have_text("Event created successfully.")
    expect(Event.where(event_type: "other").pluck(:title)).to eq(["Other"])
  end

  it "clears a title that ends with 'for' and the names of the staff", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-18T09:00")
    fill_datetime("end_time_field", "2027-03-18T10:00")
    select "Other", from: "event_type_select"
    find("#title", visible: :all).execute_script("this.value = 'Soldering for Wanda Worker, Ada Admin'")
    click_button "Save Draft"

    expect(page).to have_text("Event created successfully.")
    expect(Event.where(event_type: "other").pluck(:title)).to eq(["Other"])
  end

  it "keeps a title that only partly matches the staff names", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-18T09:00")
    fill_datetime("end_time_field", "2027-03-18T10:00")
    select "Other", from: "event_type_select"
    find("#title", visible: :all).execute_script("this.value = 'Soldering for Wanda'")
    click_button "Save Draft"

    expect(page).to have_text("Event created successfully.")
    expect(Event.where(event_type: "other").pluck(:title)).to eq(["Soldering for Wanda"])
  end

  it "refuses to save while the end is not after the start, and recovers when it is fixed", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:00")
    fill_datetime("end_time_field", "2027-03-17T09:00")

    expect(page).to have_css("#time_error:not(.d-none)")
    expect(page).to have_css("#save_button[disabled].disabled")

    fill_datetime("end_time_field", "2027-03-17T11:00")

    expect(page).to have_css("#time_error.d-none", visible: :all)
    expect(page).to have_no_css("#save_button[disabled]")
  end

  it "turns all-day into midnight-to-midnight and back into a one-hour slot", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:30")
    check "all_day_checkbox"

    expect(field_value("start_time_field")).to eq("2027-03-17T00:00")
    expect(field_value("end_time_field")).to eq("2027-03-18T00:00")
    expect(page).to have_field("end_time_field", disabled: true)

    uncheck "all_day_checkbox"

    expect(page).to have_field("end_time_field", disabled: false)
    expect(field_value("start_time_field")).to eq("2027-03-17T00:00")
    expect(field_value("end_time_field")).to eq("2027-03-17T01:00")
  end

  it "does not send the end time of an all-day event (the field is disabled)", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:30")
    check "all_day_checkbox"
    select "Other", from: "event_type_select"
    click_button "Save Draft"

    expect(page).to have_text("Event created successfully.")
    event = Event.find_by!(event_type: "other")
    expect(event.start_time).to eq(browser_utc("2027-03-17T00:00"))
    expect(event.end_time).to eq(browser_utc("2027-03-18T00:00"))
  end

  it "shows the training fields only for the training type", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal

    expect(page).to have_css("#training-fields", visible: :hidden)
    select "Training", from: "event_type_select"
    expect(page).to have_css("#training-fields", visible: :visible)
    expect(page).to have_field("training_select")
    select "Meeting", from: "event_type_select"
    expect(page).to have_css("#training-fields", visible: :hidden)
  end

  it "reveals the day checkboxes for a weekly repeat and ticks the weekday of the start", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:00")
    fill_datetime("end_time_field", "2027-03-17T11:00")

    expect(page).to have_css("#recurrence_options", visible: :hidden)
    select "Weekly", from: "recurrence_frequency"

    expect(page).to have_css("#recurrence_options", visible: :visible)
    expect(page).to have_css("#weekly_options", visible: :visible)
    expect(page).to have_checked_field("day_WE")
    expect(page).to have_unchecked_field("day_MO")

    select "Daily", from: "recurrence_frequency"
    expect(page).to have_css("#weekly_options", visible: :hidden)
    expect(page).to have_css("#recurrence_options", visible: :visible)

    select "Does not repeat", from: "recurrence_frequency"
    expect(page).to have_css("#recurrence_options", visible: :hidden)
  end

  it "warns when no weekday is ticked and clears the warning when one is", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:00")
    fill_datetime("end_time_field", "2027-03-17T11:00")
    select "Weekly", from: "recurrence_frequency"

    uncheck "day_WE"
    expect(page).to have_css("#day_freq_error:not(.d-none)")
    check "day_MO"
    expect(page).to have_css("#day_freq_error.d-none", visible: :all)
  end

  it "saves a weekly series on the ticked days", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:00")
    fill_datetime("end_time_field", "2027-03-17T11:00")
    select "Shift", from: "event_type_select"
    select "Weekly", from: "recurrence_frequency"
    check "day_FR"
    click_button "Save Draft"

    expect(page).to have_text("Event created successfully.")
    event = Event.find_by!(event_type: "shift")
    expect(event.recurrence_rule).to include("FREQ=WEEKLY")
    expect(event.recurrence_rule).to match(/BYDAY=(WE,FR|FR,WE)/)
    expect(event.recurrence_rule).not_to include("UNTIL")
  end

  it "saves an end date for a daily series as the end of that day", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:00")
    fill_datetime("end_time_field", "2027-03-17T11:00")
    select "Other", from: "event_type_select"
    select "Daily", from: "recurrence_frequency"
    find("#recurrence_until").set(Date.new(2027, 3, 25))
    click_button "Save Draft"

    expect(page).to have_text("Event created successfully.")
    rule = Event.find_by!(event_type: "other").recurrence_rule
    expect(rule).to include("FREQ=DAILY")
    until_time = Time.strptime(rule[/UNTIL=(\d{8}T\d{6}Z)/, 1], "%Y%m%dT%H%M%SZ").utc
    expect(until_time).to eq(browser_utc("2027-03-25T23:59:59"))
  end

  it "shows a new draft with a pencil mark after saving", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T14:00")
    fill_datetime("end_time_field", "2027-03-17T15:00")
    select "Meeting", from: "event_type_select"
    click_button "Save Draft"

    expect(page).to have_text("Event created successfully.")
    expect(page).to have_css(".fc-timegrid-event", text: "✎ Meeting", visible: :all)
  end

  it "asks before closing the modal and keeps it open when the answer is no", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:00")

    dismiss_confirm("Are you sure you want to exit? All changes will be lost.") do
      click_button "Cancel"
    end

    expect(page).to have_css("#eventModal.show")
    expect(field_value("start_time_field")).to eq("2027-03-17T10:00")
  end

  it "resets the form and its recurrence options after the modal closes", js: true, skip_bullet: true do
    open_admin_calendar
    open_add_modal
    fill_datetime("start_time_field", "2027-03-17T10:00")
    fill_datetime("end_time_field", "2027-03-17T11:00")
    select "Weekly", from: "recurrence_frequency"
    check "all_day_checkbox"

    accept_confirm { click_button "Cancel" }
    confirm_modal_hidden

    expect(page).to have_css("#recurrence_options", visible: :hidden)
    expect(page).to have_css("#weekly_options", visible: :hidden)
    expect(page).to have_select("recurrence_frequency", selected: "Does not repeat", visible: :all)
    expect(page).to have_unchecked_field("all_day_checkbox", visible: :all)
    expect(Event.count).to eq(0)
  end

  describe "staff unavailable at the chosen time" do
    let(:slot_start) { "2027-03-17T17:30" }
    let(:slot_end) { "2027-03-17T18:00" }

    # The unavailability is placed around the slot as the browser reads it, so
    # the examples hold in any browser time zone. The page is loaded first
    # (the browser has to compute the instants) and loaded again afterwards.
    def unavailability_around_slot(rule_for: nil)
      log_in_as(admin)
      visit root_path
      from = browser_utc(slot_start) - 1.hour
      to = browser_utc(slot_end) + 1.hour
      attrs = { user: worker, title: "Class", start_time: from, end_time: to }
      if rule_for
        day = %w[SU MO TU WE TH FR SA][(from - 7.days).wday]
        attrs[:start_time] = from - 7.days
        attrs[:end_time] = to - 7.days
        attrs[:recurrence_rule] = "DTSTART:#{(from - 7.days).strftime('%Y%m%dT%H%M%SZ')}\nRRULE:#{rule_for.sub("<day>", day)}"
      end
      create(:staff_unavailability, **attrs)
    end

    def start_modal_with_slot
      show_week_of_march_14("fullCalendarDefaultDateAdmin", admin_calendar_index_path)
      expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 14 – 20, 2027")
      wait_for_admin_calendar_scripts
      open_add_modal
      fill_datetime("start_time_field", slot_start)
      fill_datetime("end_time_field", slot_end)
    end

    def staff_options
      find("#staff_select + .ts-wrapper .ts-control").click
      page.all(".ts-dropdown .option").map(&:text)
    end

    it "marks a staff member whose one-off unavailability overlaps the slot and lists them after the free ones", js: true, skip_bullet: true do
      unavailability_around_slot
      start_modal_with_slot

      options = staff_options
      expect(options.first).to include("Ada Admin")
      expect(options.first).not_to include("Unavailable")
      expect(options.last).to include("Wanda Worker")
      expect(options.last).to include("(Unavailable")
    end

    it "marks nobody when the slot is clear of the unavailability", js: true, skip_bullet: true do
      unavailability_around_slot
      show_week_of_march_14("fullCalendarDefaultDateAdmin", admin_calendar_index_path)
      open_add_modal
      fill_datetime("start_time_field", "2027-03-19T09:00")
      fill_datetime("end_time_field", "2027-03-19T10:00")

      expect(staff_options.join).not_to include("Unavailable")
    end

    it "marks a staff member with a repeating unavailability for a one-off slot on one of its days", js: true, skip_bullet: true do
      unavailability_around_slot(rule_for: "FREQ=WEEKLY;BYDAY=<day>")
      start_modal_with_slot

      expect(staff_options.last).to include("(Unavailable")
    end

    it "marks a staff member for a repeating slot that meets their one-off unavailability", js: true, skip_bullet: true do
      unavailability_around_slot
      start_modal_with_slot
      select "Daily", from: "recurrence_frequency"

      expect(staff_options.last).to include("(Unavailable")
    end

    # Two repeating rules are compared only over the four weeks after today, so a
    # slot further ahead than that (this one is in March 2027) is never marked.
    it "does not mark a staff member when two repeating rules only meet more than four weeks from today", js: true, skip_bullet: true do
      unavailability_around_slot(rule_for: "FREQ=WEEKLY;BYDAY=<day>")
      start_modal_with_slot
      select "Daily", from: "recurrence_frequency"

      expect(staff_options.join).not_to include("Unavailable")
    end
  end
end
