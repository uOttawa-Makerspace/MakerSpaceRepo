# frozen_string_literal: true

require "rails_helper"

# A weekly series on the admin calendar (events) and on the staff unavailabilities page, in the two weeks of 2027
# that hold a clock change in Toronto: the week of Sunday 2027-03-14 (02:00 becomes 03:00) and the week of Sunday
# 2027-11-07 (02:00 becomes 01:00). The admin calendar hands an event series' repeat rule to the browser, which draws
# it with @fullcalendar/rrule; the staff unavailabilities page draws the occurrences the server expands
# (RecurringSeries). The dialogs then post the instant of the occurrence that was clicked. These examples pin what a
# person sees and what is saved, including where the admin page and the server disagree. Each disagreement is named
# in a comment, and the slice that moves the event expansion to the server changes those examples and nothing else.
#
# The admin calendar's week view starts at 07:00, so a 01:30 or 02:30 series is only drawn in its month view; the
# examples use the month view there and the week view on the staff page.
RSpec.describe "Recurring events across the clock changes", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space, name: "Calendar Lab") }
  let!(:admin) { create(:user, :admin, name: "Ada Admin", space_id: space.id) }
  let!(:staff) { create(:user, :staff, name: "Wanda Worker", space_id: space.id) }
  let(:eastern) { Time.zone }

  before do
    create(:staff_space, user: admin, space: space)
    create(:staff_space, user: staff, space: space, color: "#cc3300")
  end

  # The weeks shown, the day the server's clock is frozen at, and the series: weekly on Sundays from the Sunday
  # before the clock change, so the change day is its second occurrence.
  def weeks
    {
      forward: { title: { admin: "March 2027", staff: "Mar 14 – 20, 2027" }, middle: "2027-03-16T12:00:00.000Z",
                 now: [2027, 3, 16, 12], first: [2027, 3, 7, 2, 30], rule_start: "20270307T073000Z",
                 change_day: "2027-03-14", marker_day: [2027, 3, 17] },
      back: { title: { admin: "November 2027", staff: "Nov 7 – 13, 2027" }, middle: "2027-11-09T17:00:00.000Z",
              now: [2027, 11, 9, 12], first: [2027, 10, 31, 1, 30], rule_start: "20271031T053000Z",
              change_day: "2027-11-07", marker_day: [2027, 11, 10] }
    }
  end

  def pages
    {
      admin: { title: "Sunday lab", storage_key: "fullCalendarDefaultDateAdmin",
               occurrence: ".fc-daygrid-day[data-date='%s'] .fc-daygrid-event" },
      staff: { title: "Sunday class", storage_key: "fullCalendarDefaultDateStaffUnavailabilities",
               occurrence: ".fc-timegrid-col[data-date='%s'] .fc-timegrid-event" }
    }
  end

  # A one-off entry on a weekday of the week. It marks that the page has finished drawing, so the examples that wait
  # for an occurrence to go can tell a page still loading from one without the occurrence.
  def create_marker(page_kind, week)
    day = weeks.fetch(week)[:marker_day]
    if page_kind == :admin
      create(:event, space: space, title: "Marker", event_type: "other", draft: false,
                     start_time: eastern.local(*day, 10), end_time: eastern.local(*day, 11))
    else
      create(:staff_unavailability, user: staff, title: "Marker", start_time: eastern.local(*day, 10), end_time: eastern.local(*day, 11))
    end
  end

  def create_series(page_kind, week)
    first = eastern.local(*weeks.fetch(week)[:first])
    rule = "DTSTART:#{weeks.fetch(week)[:rule_start]}\nRRULE:FREQ=WEEKLY;BYDAY=SU"
    if page_kind == :admin
      create(:event, space: space, title: pages[:admin][:title], event_type: "other", draft: false,
                     start_time: first, end_time: first + 1.hour, recurrence_rule: rule)
    else
      create(:staff_unavailability, user: staff, title: pages[:staff][:title],
                                    start_time: first, end_time: first + 1.hour, recurrence_rule: rule)
    end
  end

  def show_week(page_kind, week)
    find(".fc-dayGridMonth-button").click if page_kind == :admin
    expect(page).to have_css("#calendar .fc-toolbar-title", text: weeks.fetch(week)[:title].fetch(page_kind))
    expect(page).to have_css(".fc-event", text: "Marker", visible: :all)
  end

  def open_calendar(page_kind, week)
    storage = { pages.fetch(page_kind)[:storage_key] => weeks.fetch(week)[:middle] }
    if page_kind == :admin
      log_in_as(admin, to: admin_calendar_index_path, local_storage: storage)
      wait_for_admin_calendar_scripts
    else
      log_in_as(staff, to: staff_unavailabilities_path, local_storage: storage)
    end
    show_week(page_kind, week)
  end

  def occurrence_css(page_kind, week)
    format(pages.fetch(page_kind)[:occurrence], weeks.fetch(week)[:change_day])
  end

  def change_day_event(page_kind, week)
    page.find(occurrence_css(page_kind, week), text: pages.fetch(page_kind)[:title], visible: :all)
  end

  def open_change_day_event(page_kind, week)
    change_day_event(page_kind, week).click
    shown = page_kind == :admin ? "#eventModal[data-shown='true']" : "#unavailabilityModal.show"
    expect(page).to have_css(shown)
    # a document the form submit replaces does not have this mark
    page.execute_script("document.body.dataset.beforeReload = '1'")
  end

  # The submit replaces the page: wait for the new document, then for the calendar to draw again.
  def wait_for_reload(page_kind, week)
    expect(page).to have_no_css("body[data-before-reload]", visible: :all)
    wait_for_admin_calendar_scripts if page_kind == :admin
    show_week(page_kind, week)
  end

  def choose_delete(label)
    click_button "Delete"
    click_button label
  end

  def edit_title_for_all(new_title)
    open_custom_values
    fill_in "title", with: new_title
    find("#update_dropdown > button").click
    choose "update_all"
    click_button "Update"
  end

  %i[admin staff].each do |page_kind|
    describe "on the #{page_kind == :admin ? 'admin calendar' : 'staff unavailabilities page'}", browser_zone: "America/Toronto" do
      let!(:series) { create_series(page_kind, week) }
      let(:title) { pages.fetch(page_kind)[:title] }

      around { |example| travel_to(eastern.local(*weeks.fetch(week)[:now])) { example.run } }

      before { create_marker(page_kind, week) }

      describe "in the week the clocks go forward (2027-03-14)" do
        let(:week) { :forward }

        # The change-day occurrence of a 02:30 series: the admin page repeats the wall time 02:30 and draws it at
        # 02:30, an hour that does not exist that night (disagreement "skipped hour"); the staff page draws the
        # server's occurrence at 03:30, as the staff calendar and the shifts API have it.
        let(:change_day_time) { { admin: "02:30", staff: "03:30" }.fetch(page_kind) }

        it "draws the 02:30 series on the change day and fills the form with that occurrence's time", js: true, skip_bullet: true do
          open_calendar(page_kind, week)
          expect(change_day_event(page_kind, week).text).to include(change_day_time.delete_prefix("0"))
          open_change_day_event(page_kind, week)

          expect(field_value("start_time_field")).to eq("2027-03-14T#{change_day_time}")
        end

        # The dialog posts the instant of the clicked occurrence, 03:30 daylight time (07:30Z), and the server stores
        # that exclusion. The staff page draws the server's occurrences, so the deleted one is gone. Disagreement
        # "deleted occurrence stays visible" on the admin page: it turns the exclusion into the wall time 03:30,
        # which no occurrence of its 02:30 repeat has, so the occurrence is still drawn after the page reloads.
        it "removes the occurrence deleted with 'This event' from the staff page only", js: true, skip_bullet: true do
          open_calendar(page_kind, week)
          open_change_day_event(page_kind, week)
          choose_delete("This event")
          eventually { series.reload.recurrence_rule.include?("EXDATE") }
          wait_for_reload(page_kind, week)

          # Every dialog delete or update-all writes the start line in the one form edits use,
          # DTSTART;TZID=America/Toronto with the Toronto wall time, so the exact rules below start that way.
          expect(series.reload.recurrence_rule).to eq("DTSTART;TZID=America/Toronto:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20270314T073000Z")
          if page_kind == :admin
            expect(change_day_event(page_kind, week).text).to include("2:30")
          else
            expect(page).to have_no_css(occurrence_css(page_kind, week), text: title, visible: :all)
          end
        end

        # Only the title is edited: the form holds the occurrence as filled and sends the series' own start and length, so
        # the series is renamed and keeps its 02:30 start (the admin page's form holds 02:30 to 03:30 there, the staff
        # page's 03:30 to 04:30).
        it "saves 'Update all events' with only the title changed from the change-day occurrence", js: true, skip_bullet: true do
          open_calendar(page_kind, week)
          open_change_day_event(page_kind, week)
          edit_title_for_all("Renamed series")
          wait_for_reload(page_kind, week)
          series.reload

          expect([series.title, series.start_time, series.recurrence_rule]).to eq(
            ["Renamed series", eastern.local(2027, 3, 7, 2, 30), "DTSTART;TZID=America/Toronto:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU"]
          )
        end

        it "ends the series with 'This and following events'", js: true, skip_bullet: true do
          open_calendar(page_kind, week)
          open_change_day_event(page_kind, week)
          choose_delete("This and following events")
          eventually { series.reload.recurrence_rule.include?("UNTIL=") }
          wait_for_reload(page_kind, week)

          expect(series.reload.recurrence_rule).to eq("DTSTART;TZID=America/Toronto:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU;UNTIL=20270313T073000Z")
        end
      end

      describe "in the week the clocks go back (2027-11-07)" do
        let(:week) { :back }

        it "draws the 01:30 series once on the change day and fills the form with 01:30", js: true, skip_bullet: true do
          open_calendar(page_kind, week)
          expect(page).to have_css(occurrence_css(page_kind, week), text: title, count: 1, visible: :all)
          open_change_day_event(page_kind, week)

          expect(field_value("start_time_field")).to eq("2027-11-07T01:30")
        end

        it "stops drawing the occurrence deleted with 'This event'", js: true, skip_bullet: true do
          open_calendar(page_kind, week)
          open_change_day_event(page_kind, week)
          choose_delete("This event")
          eventually { series.reload.recurrence_rule.include?("EXDATE") }
          wait_for_reload(page_kind, week)

          expect(series.reload.recurrence_rule).to eq("DTSTART;TZID=America/Toronto:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20271107T053000Z")
          expect(page).to have_no_css(occurrence_css(page_kind, week), text: title, visible: :all)
        end

        it "renames every occurrence with 'Update all events'", js: true, skip_bullet: true do
          open_calendar(page_kind, week)
          open_change_day_event(page_kind, week)
          edit_title_for_all("Renamed series")
          wait_for_reload(page_kind, week)
          series.reload

          expect([series.title, series.start_time, series.recurrence_rule]).to eq(["Renamed series", eastern.local(2027, 10, 31, 1, 30), "DTSTART;TZID=America/Toronto:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU"])
          # Both dialogs send the series' own length (the form showed 01:30 to 02:30, two real hours that night).
          expect(series.end_time - series.start_time).to eq(1.hour)
        end

        it "ends the series with 'This and following events'", js: true, skip_bullet: true do
          open_calendar(page_kind, week)
          open_change_day_event(page_kind, week)
          choose_delete("This and following events")
          eventually { series.reload.recurrence_rule.include?("UNTIL=") }
          wait_for_reload(page_kind, week)

          expect(series.reload.recurrence_rule).to eq("DTSTART;TZID=America/Toronto:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU;UNTIL=20271106T053000Z")
          expect(page).to have_no_css(occurrence_css(page_kind, week), text: title, visible: :all)
        end
      end
    end
  end
end
