# frozen_string_literal: true

require "rails_helper"

# Clicking an event on the admin calendar opens the same modal in edit mode
# (calendar_helper.js eventClick): the form is filled from the event, the save
# button becomes "Update", and the publish and delete buttons appear.

RSpec.describe "Admin calendar: editing and deleting events", type: :system do
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

  let!(:single) do
    create(:event, space: space, title: "Team sync", event_type: "meeting", draft: false,
                   description: "Weekly catch-up",
                   start_time: eastern.local(2027, 3, 16, 10), end_time: eastern.local(2027, 3, 16, 11))
  end

  def open_admin_calendar
    log_in_as(admin)
    show_week_of_march_14("fullCalendarDefaultDateAdmin", admin_calendar_index_path)
    expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 14 – 20, 2027")
  end

  def open_event(title, index: 0)
    expect(page).to have_css(".fc-timegrid-event", text: title, visible: :all)
    page.all(".fc-timegrid-event", text: title, visible: :all)[index].click
    expect(page).to have_css("#eventModal.show")
  end

  def create_series(title: "Open lab", rule: "DTSTART:20270315T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20270331T235959Z")
    create(:event, space: space, title: title, event_type: "other", draft: false,
                   start_time: eastern.local(2027, 3, 15, 10), end_time: eastern.local(2027, 3, 15, 11),
                   recurrence_rule: rule)
  end

  describe "a single event" do
    it "fills the modal from the event and switches it to edit mode", js: true, skip_bullet: true do
      create(:event_assignment, event: single, user: worker)
      open_admin_calendar
      open_event("Team sync")

      expect(page).to have_css("#eventModalLabel", text: "Edit Event")
      expect(find("#title", visible: :all).value).to eq("Team sync")
      expect(find("#description", visible: :all).value).to eq("Weekly catch-up")
      expect(find("#event_type_select").value).to eq("meeting")
      expect(find("#save_button").value).to eq("Update")
      expect(find("#eventForm", visible: :all)[:action]).to end_with("/admin/events/#{single.id}")
      expect(find("#eventForm input[name=_method]", visible: :all).value).to eq("patch")
      expect(field_value("start_time_field")).to eq(browser_local(single.start_time))
      expect(field_value("end_time_field")).to eq(browser_local(single.end_time))
      expect(page).to have_css("#staff_select + .ts-wrapper .item", text: "Wanda Worker")
      expect(page).to have_css("#publish_and_delete_forms", visible: :visible)
      expect(page).to have_css("#delete_single_form", visible: :all)
      expect(page).to have_css("#delete_following_form", visible: :hidden)
      expect(page).to have_css("#delete_all_form", visible: :hidden)
      expect(page).to have_css("#publish_form", visible: :hidden)
    end

    it "keeps the pencil mark out of the title field of a draft and offers to publish it", js: true, skip_bullet: true do
      single.update!(draft: true)
      open_admin_calendar
      open_event("Team sync")

      expect(find("#title", visible: :all).value).to eq("Team sync")
      expect(page).to have_css("#publish_form", visible: :visible)
      expect(find("#publish_form", visible: :all)[:action]).to end_with("/admin/events/#{single.id}/publish")
    end

    it "publishes a draft from the modal", js: true, skip_bullet: true do
      single.update!(draft: true)
      open_admin_calendar
      open_event("Team sync")
      click_button "Publish"

      expect(page).to have_text("Event published successfully.")
      expect(single.reload.draft).to be(false)
    end

    it "saves changes to the title, the type and the assigned staff", js: true, skip_bullet: true do
      create(:event_assignment, event: single, user: worker)
      open_admin_calendar
      open_event("Team sync")
      open_custom_values
      fill_in "title", with: "Team retro"
      select "Other", from: "event_type_select"
      find("#staff_select + .ts-wrapper .item", text: "Wanda Worker").find(".remove").click
      find("#staff_select + .ts-wrapper .ts-control").click
      find(".ts-dropdown .option", text: "Ada Admin").click
      click_button "Update"

      expect(page).to have_text("Event updated successfully.")
      single.reload
      expect(single.title).to eq("Team retro")
      expect(single.event_type).to eq("other")
      expect(single.users).to contain_exactly(admin)
    end

    it "moves the event when the times are changed", js: true, skip_bullet: true do
      open_admin_calendar
      open_event("Team sync")
      fill_datetime("start_time_field", "2027-03-18T15:00")
      fill_datetime("end_time_field", "2027-03-18T16:00")
      click_button "Update"

      expect(page).to have_text("Event updated successfully.")
      expect(single.reload.start_time).to eq(browser_utc("2027-03-18T15:00"))
      expect(single.end_time).to eq(browser_utc("2027-03-18T16:00"))
    end

    it "shows an all-day event with the end field locked", js: true, skip_bullet: true do
      single.update!(title: "Closed", start_time: eastern.local(2027, 3, 17, 0), end_time: eastern.local(2027, 3, 18, 0))
      open_admin_calendar
      expect(page).to have_css(".fc-daygrid-event", text: "Closed", visible: :all)
      find(".fc-daygrid-event", text: "Closed", visible: :all).click
      expect(page).to have_css("#eventModal.show")

      expect(page).to have_checked_field("all_day_checkbox")
      expect(page).to have_field("end_time_field", disabled: true)
    end

    it "deletes an event that does not repeat", js: true, skip_bullet: true do
      open_admin_calendar
      open_event("Team sync")
      click_button "Delete"
      click_button "This event"

      expect(page).to have_text("Event deleted.")
      expect(Event.exists?(single.id)).to be(false)
    end
  end

  describe "a repeating event" do
    it "restores the repeat rule, its weekdays and its end date", js: true, skip_bullet: true do
      create_series
      open_admin_calendar
      open_event("Open lab", index: 1)

      expect(find("#recurrence_frequency", visible: :all).value).to eq("WEEKLY")
      expect(page).to have_css("#weekly_options", visible: :visible)
      expect(page).to have_checked_field("day_MO", visible: :all)
      expect(page).to have_checked_field("day_WE", visible: :all)
      expect(page).to have_unchecked_field("day_TU", visible: :all)
      expect(field_value("recurrence_until")).to eq("2027-03-31")
      expect(field_value("recurrence_rule_field")).to include("FREQ=WEEKLY")
    end

    it "moves the save button into the scope menu and offers all three delete choices", js: true, skip_bullet: true do
      create_series
      open_admin_calendar
      open_event("Open lab", index: 1)

      expect(page).to have_css("#update_dropdown", visible: :visible)
      expect(page).to have_css("#dropdown_save_button_container #save_button", visible: :all)
      expect(find("#save_button", visible: :all).value).to eq("Update")
      click_button "Delete"
      expect(page).to have_button("This event")
      expect(page).to have_button("This and following events")
      expect(page).to have_button("All events")
    end

    it "updates only the clicked occurrence by default, leaving a separate event", js: true, skip_bullet: true do
      series = create_series
      open_admin_calendar
      open_event("Open lab", index: 1)
      open_custom_values
      fill_in "title", with: "Open lab (special)"
      find("#update_dropdown > button").click
      expect(page).to have_checked_field("update_this")
      click_button "Update"

      expect(page).to have_text("This event occurrence updated successfully.")
      expect(Event.where(title: "Open lab (special)").count).to eq(1)
      expect(series.reload.title).to eq("Open lab")
      expect(series.recurrence_rule).to include("EXDATE")
    end

    it "updates every occurrence when 'Update all events' is chosen", js: true, skip_bullet: true do
      series = create_series
      open_admin_calendar
      open_event("Open lab", index: 1)
      open_custom_values
      fill_in "title", with: "Open lab (all)"
      find("#update_dropdown > button").click
      choose "update_all"
      click_button "Update"

      expect(page).to have_text("Unavailability updated successfully.")
      expect(series.reload.title).to eq("Open lab (all)")
      expect(Event.count).to eq(2)
    end

    it "removes one occurrence by excluding its date", js: true, skip_bullet: true do
      series = create_series
      open_admin_calendar
      open_event("Open lab", index: 1)
      click_button "Delete"
      click_button "This event"

      expect(page).to have_text("This occurrence deleted.")
      # the excluded instant is the wall-clock time read as UTC (10:00Z), not the occurrence (14:00Z)
      expect(series.reload.recurrence_rule).to include("EXDATE:20270317T100000Z")
      expect(page).to have_css(".fc-timegrid-event", text: "Open lab", count: 2, visible: :all)
    end

    it "ends the series the day before when 'This and following events' is chosen", js: true, skip_bullet: true do
      series = create_series
      open_admin_calendar
      open_event("Open lab", index: 1)
      click_button "Delete"
      click_button "This and following events"

      expect(page).to have_text("This and following deleted.")
      expect(series.reload.recurrence_rule).to include("UNTIL=20270316T100000Z")
    end

    it "deletes the whole series when 'All events' is chosen", js: true, skip_bullet: true do
      series = create_series
      open_admin_calendar
      open_event("Open lab", index: 1)
      click_button "Delete"
      click_button "All events"

      expect(page).to have_text("Event series deleted.")
      expect(Event.exists?(series.id)).to be(false)
    end
  end

  describe "a staff unavailability shown on the admin calendar" do
    let!(:unavail) do
      create(:staff_unavailability, user: worker, title: "Lecture", description: "Calculus",
                                    start_time: eastern.local(2027, 3, 17, 13), end_time: eastern.local(2027, 3, 17, 15))
    end

    it "opens in the unavailability form with the type locked and the owner as the only staff", js: true, skip_bullet: true do
      open_admin_calendar
      open_event("Lecture")

      expect(page).to have_css("#eventModalLabel", text: "Edit Unavailability")
      expect(find("#event_type_select").value).to eq("unavailability")
      expect(page).to have_field("event_type_select", disabled: true)
      expect(page).to have_css(".lock-indicator", text: "Unavailability type cannot be changed")
      expect(find("#eventForm", visible: :all)[:action]).to end_with("/staff/unavailabilities/#{unavail.id}")
      expect(page).to have_css("#staff_select + .ts-wrapper .item", text: "Wanda Worker")
      expect(find("#staff_select", visible: :all)[:name]).to eq("staff_unavailability[user_id]")
      expect(find("#title", visible: :all)[:name]).to eq("staff_unavailability[title]")
      expect(page).to have_css("#publish_form", visible: :hidden)
      expect(find("#delete_single_form", visible: :all)[:action]).to end_with("/staff/unavailabilities/#{unavail.id}/delete_with_scope")
    end

    # Saving logs an uncaught TypeError from the staff select (an option without its unavailable dates); the save still goes through.
    it "saves a change to its description through the unavailability endpoint", js: true, skip_bullet: true, js_errors: :allow do
      open_admin_calendar
      open_event("Lecture")
      open_custom_values
      fill_in "description", with: "Calculus tutorial"
      click_button "Update"

      eventually { unavail.reload.description == "Calculus tutorial" }
      expect(unavail.reload.description).to eq("Calculus tutorial")
    end

    # The title field is filled with the calendar's own label ("<icon> <name> - <title>"),
    # so every save writes that label back as the title.
    it "fills the title field with the calendar label and saves it back as the title", js: true, skip_bullet: true, js_errors: :allow do
      open_admin_calendar
      open_event("Lecture")
      expect(find("#title", visible: :all).value).to eq("🚫 Wanda Worker - Lecture")
      click_button "Update"

      eventually { unavail.reload.title != "Lecture" }
      expect(unavail.reload.title).to eq("🚫 Wanda Worker - Lecture")
    end

    it "deletes it from the modal", js: true, skip_bullet: true do
      open_admin_calendar
      open_event("Lecture")
      click_button "Delete"
      click_button "This event"

      expect(page).to have_text("Unavailability deleted.")
      expect(StaffUnavailability.exists?(unavail.id)).to be(false)
    end
  end

  describe "choosing a type while editing" do
    it "switches the form fields to the unavailability names when Unavailability is chosen", js: true, skip_bullet: true do
      open_admin_calendar
      open_event("Team sync")
      select "Unavailability", from: "event_type_select"

      expect(find("#title", visible: :all)[:name]).to eq("staff_unavailability[title]")
      expect(find("#staff_select", visible: :all)[:name]).to eq("staff_unavailability[user_id]")
      expect(find("#eventForm", visible: :all)[:action]).to end_with("/admin/events/#{single.id}")
    end

    it "shows the training fields when Training is chosen and hides them for another type", js: true, skip_bullet: true do
      open_admin_calendar
      open_event("Team sync")
      select "Training", from: "event_type_select"
      expect(page).to have_css("#training-fields", visible: :visible)
      select "Shift", from: "event_type_select"
      expect(page).to have_css("#training-fields", visible: :hidden)
    end
  end

  describe "a training event" do
    it "fills in the training, language and course", js: true, skip_bullet: true do
      training = create(:training, name_en: "Laser safety")
      create(:spaces_training, space: space, training: training) if FactoryBot.factories.registered?(:spaces_training)
      course = create(:course_name, name: "GNG1103")
      event = create(:event, :training, space: space, training: training, course_name: course, language: "en",
                                        title: "Laser night", draft: false,
                                        start_time: eastern.local(2027, 3, 17, 18), end_time: eastern.local(2027, 3, 17, 19))
      open_admin_calendar
      open_event("Laser night")

      expect(page).to have_css("#training-fields", visible: :visible)
      expect(find("#language_select", visible: :all).value).to eq("en")
      expect(find("#course_select", visible: :all).value).to eq(course.id.to_s)
      expect(event.reload.training_id).to eq(training.id)
    end
  end
end
