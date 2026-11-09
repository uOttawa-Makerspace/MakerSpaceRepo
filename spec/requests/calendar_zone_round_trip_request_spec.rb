# frozen_string_literal: true

require "rails_helper"

# The server half of the calendar time round trip. The modal posts UTC instants
# and the feeds send them back in Toronto time; delete-with-scope stamps the
# instant the modal sends. None of it may depend on the zone of the server
# process, so every example runs with the process clock in Toronto, in UTC and
# in Tokyo. The cases come from spec/fixtures/calendar_dst_cases.json, which
# the Vitest calendar specs also read.
RSpec.describe "Calendar times whatever the server process zone", type: :request do
  include SpacesSpecHelpers

  cases = JSON.parse(Rails.root.join("spec/fixtures/calendar_dst_cases.json").read)
  zones = { "America/Toronto" => -4, "UTC" => 0, "Asia/Tokyo" => 9 }

  let!(:space) { create(:space) }

  def an_hour_after(instant) = (Time.iso8601(instant) + 1.hour).utc.iso8601
  def stamp(instant) = Time.iso8601(instant).utc.strftime("%Y%m%dT%H%M%SZ")
  def field_of(iso) = iso[0, 16]
  def admin_rows = response.parsed_body.flat_map { |group| group["events"] }

  # A weekly series on Wednesdays at 10:00 Toronto time, written the way the
  # modal writes it (UTC stamps)
  let(:series_rule) { "DTSTART:20270303T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=WE" }
  let(:series_start) { Time.utc(2027, 3, 3, 15) }

  zones.each do |zone, offset_on_17_march|
    context "with the server process in #{zone}" do
      around do |example|
        original = ENV.fetch("TZ", nil)
        ENV["TZ"] = zone
        example.run
      ensure
        ENV["TZ"] = original
      end

      it "has that zone" do
        expect(Time.local(2027, 3, 17, 12).utc_offset).to eq(offset_on_17_march * 3600)
      end

      describe "an event" do
        before { sign_in_as(:admin) }

        cases["instantToField"].each do |c|
          it "saved at #{c['label']} is stored at that instant and shown at its Toronto time" do
            post admin_events_path, params: { event: { event_type: "meeting", title: "Meeting", space_id: space.id,
                                                       utc_start_time: c["instant"], utc_end_time: an_hour_after(c["instant"]) } }
            event = Event.last
            expect(event.start_time).to eq(Time.iso8601(c["instant"]))

            get json_admin_events_path(id: space.id)
            row = admin_rows.find { |r| r["id"] == "event-#{event.id}" }
            expect(field_of(row["start"])).to eq(c["field"])
          end
        end

        cases["calendarStrings"].each do |c|
          it "excludes #{c['label']} by the instant the modal sends" do
            series = create(:event, space: space, start_time: series_start, end_time: series_start + 1.hour,
                                    recurrence_rule: series_rule)
            delete delete_with_scope_admin_event_path(series), params: { scope: "single", start_date: c["instant"] }
            expect(series.reload.recurrence_rule).to eq("#{series_rule}\nEXDATE:#{stamp(c['instant'])}")
          end

          it "ends the series a day before #{c['label']}" do
            series = create(:event, space: space, start_time: series_start, end_time: series_start + 1.hour,
                                    recurrence_rule: series_rule)
            delete delete_with_scope_admin_event_path(series), params: { scope: "following", start_date: c["instant"] }
            until_stamp = (Time.iso8601(c["instant"]) - 1.day).utc.strftime("%Y%m%dT%H%M%SZ")
            expect(series.reload.recurrence_rule).to eq("#{series_rule};UNTIL=#{until_stamp}")
          end
        end
      end

      describe "an unavailability" do
        let!(:staff) { sign_in_as(:staff) }

        cases["instantToField"].each do |c|
          it "saved at #{c['label']} is stored at that instant and shown at its Toronto time" do
            post staff_unavailabilities_path, params: { staff_unavailability: { title: "Class", utc_start_time: c["instant"],
                                                                                utc_end_time: an_hour_after(c["instant"]) } }
            unavailability = StaffUnavailability.last
            expect(unavailability.start_time).to eq(Time.iso8601(c["instant"]))

            get json_staff_unavailabilities_path
            row = response.parsed_body.find { |r| r["id"] == unavailability.id }
            expect(field_of(row["start"])).to eq(c["field"])
          end
        end

        cases["calendarStrings"].each do |c|
          it "excludes #{c['label']} by the instant the modal sends" do
            series = create(:staff_unavailability, user: staff, start_time: series_start, end_time: series_start + 1.hour,
                                                   recurrence_rule: series_rule)
            delete delete_with_scope_staff_unavailability_path(series), params: { scope: "single", start_date: c["instant"] }
            expect(series.reload.recurrence_rule).to eq("#{series_rule}\nEXDATE:#{stamp(c['instant'])}")
          end

          it "ends the series a day before #{c['label']}" do
            series = create(:staff_unavailability, user: staff, start_time: series_start, end_time: series_start + 1.hour,
                                                   recurrence_rule: series_rule)
            delete delete_with_scope_staff_unavailability_path(series), params: { scope: "following", start_date: c["instant"] }
            until_stamp = (Time.iso8601(c["instant"]) - 1.day).utc.strftime("%Y%m%dT%H%M%SZ")
            expect(series.reload.recurrence_rule).to eq("#{series_rule};UNTIL=#{until_stamp}")
          end
        end
      end

      describe "a repeat end written by the modal" do
        cases["untilDates"].each do |c|
          it "keeps the last occurrence on #{c['label']}" do
            # daily at 23:00 Toronto time, the latest hour of the day the modal offers
            start = Time.zone.parse("2027-03-01T23:00")
            rule = "DTSTART:#{start.utc.strftime('%Y%m%dT%H%M%SZ')}\nRRULE:FREQ=DAILY;UNTIL=#{c['until']}"
            found = RecurrenceExpansion.occurrences(rule, start, start, start + 1.year, 400).occurrences
            expect(found.last.strftime("%Y-%m-%d %H:%M")).to eq("#{c['date']} 23:00")
          end
        end
      end

      describe "a rule stored before the modal read Toronto time" do
        # Stored rules keep their UTC stamps: the feeds and the server expansion
        # read them exactly as before.
        let(:stored) { "DTSTART:20270315T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20270331T235959Z\nEXDATE:20270317T140000Z" }
        let(:start) { Time.utc(2027, 3, 15, 14) }

        it "is sent to the admin calendar unchanged apart from the Toronto start" do
          sign_in_as(:admin)
          event = create(:event, space: space, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
          get json_admin_events_path(id: space.id)
          row = admin_rows.find { |r| r["id"] == "event-#{event.id}" }
          expect(row["rrule"]).to eq("DTSTART:20270315T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20270331T235959Z\nEXDATE:20270317T100000")
        end

        it "expands on the server to the same instants" do
          found = RecurrenceExpansion.occurrences(stored, start.in_time_zone, start, start + 1.month, 50).occurrences
          expect(found.map { |t| t.utc.iso8601 }).to eq(
            %w[2027-03-15T14:00:00Z 2027-03-17T14:00:00Z 2027-03-22T14:00:00Z 2027-03-24T14:00:00Z
               2027-03-29T14:00:00Z 2027-03-31T14:00:00Z]
          )
        end
      end
    end
  end
end
