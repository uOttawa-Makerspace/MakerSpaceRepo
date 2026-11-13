# frozen_string_literal: true

require "rails_helper"

# Staff::UnavailabilitiesController (StaffAreaController: staff or admin).
# Times arrive as UTC strings (utc_start_time / utc_end_time) and are stored as
# UTC instants; the app zone is Eastern, so attributes read back as -05:00/-04:00
# offsets of the same instant. Recurrence rules are stored as an iCal block
# ("DTSTART:...\nRRULE:...\nEXDATE:...") in UTC.

RSpec.describe "Staff unavailabilities", type: :request do
  include SpacesSpecHelpers

  RULE = "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO"
  # RULE as the series edits write it again: the start in Toronto time
  RULE_AS_WRITTEN = "DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO"

  def payload(overrides = {})
    { staff_unavailability: { title: "Class", description: "desc",
                              utc_start_time: "2027-03-01T15:00:00Z", utc_end_time: "2027-03-01T16:00:00Z" }.merge(overrides) }
  end

  describe "auth" do
    let(:owner) { create(:user, :staff) }
    let!(:record) { create(:staff_unavailability, user: owner) }
    let(:calls) do
      {
        index: -> { get staff_unavailabilities_path },
        json: -> { get json_staff_unavailabilities_path },
        create: -> { post staff_unavailabilities_path, params: payload },
        update: -> { patch staff_unavailability_path(record), params: payload },
        destroy: -> { delete staff_unavailability_path(record) },
        delete_with_scope: -> { delete delete_with_scope_staff_unavailability_path(record), params: { scope: "all" } },
        external: -> { patch update_external_unavailabilities_staff_unavailabilities_path, params: { external_calendar: ["https://x.test/a.ics"] } }
      }
    end
    let(:state) { -> { [StaffUnavailability.order(:id).map(&:attributes), StaffExternalUnavailability.count] } }

    it "sends a guest to login with back_to on every action" do
      sign_in_as(:guest)
      calls.each do |name, call|
        before_state = state.call
        instance_exec(&call)
        expect(response).to have_http_status(:found), name.to_s
        # back_to is stored only for replayable (GET) requests; other verbs get a bare /login
        expect(response.location).to(
          integration_session.request.get? ? start_with("http://www.example.com/login?back_to=") : eq("http://www.example.com/login"),
          name.to_s
        )
        expect(state.call).to eq(before_state), name.to_s
      end
    end

    it "sends a regular user to root with an alert on every action" do
      expect_bounced(:regular, calls, state: state, to: root_path, flash_alert: "You cannot access this area.")
    end
  end

  context "as staff" do
    let!(:staff) { sign_in_as(:staff) }
    let(:other) { create(:user, :staff) }

    it "renders the index" do
      StaffExternalUnavailability.create!(user: staff, ics_url: "https://x.test/mine.ics")
      get staff_unavailabilities_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("https://x.test/mine.ics")
    end

    describe "create" do
      it "stores a UTC instant, a default title and stripped description" do
        post staff_unavailabilities_path, params: payload(title: "", description: "<b>bold</b> text")
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:notice]).to eq("Unavailability created.")
        u = StaffUnavailability.last
        expect(u).to have_attributes(user_id: staff.id, title: "Unavailable", description: "bold text", recurrence_rule: nil)
        expect(u.start_time.utc.iso8601).to eq("2027-03-01T15:00:00Z")
        expect(u.end_time.utc.iso8601).to eq("2027-03-01T16:00:00Z")
        expect(u.start_time.zone).to eq("EST")
      end

      it "treats an offset-less time string as UTC-system time and an explicit offset as that offset" do
        post staff_unavailabilities_path, params: payload(utc_start_time: "2027-03-14T01:30:00-05:00", utc_end_time: "2027-03-14T03:30:00-04:00")
        u = StaffUnavailability.last
        expect(u.start_time.utc.iso8601).to eq("2027-03-14T06:30:00Z")
        expect(u.end_time.utc.iso8601).to eq("2027-03-14T07:30:00Z") # DST gap day: 2h of wall clock is 1h
      end

      it "stores the recurrence rule verbatim" do
        post staff_unavailabilities_path, params: payload(recurrence_rule: RULE)
        expect(StaffUnavailability.last.recurrence_rule).to eq(RULE)
      end

      it "alerts for an inverted range and a weekly rule without BYDAY" do
        expect { post staff_unavailabilities_path, params: payload(utc_start_time: "2027-03-01T17:00:00Z") }.not_to change(StaffUnavailability, :count)
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:alert]).to eq("Failed to create unavailability: Start time must be before the end time")
        expect { post staff_unavailabilities_path, params: payload(recurrence_rule: "RRULE:FREQ=WEEKLY") }.not_to change(StaffUnavailability, :count)
        expect(flash[:alert]).to eq("Failed to create unavailability: Recurrence rule must include days of the week when using weekly frequency")
      end

      it "opens the create failure message in French for a French request" do
        post staff_unavailabilities_path(locale: "fr"), params: { staff_unavailability: { title: "x" } }
        expect(flash[:alert]).to start_with("Impossible de créer l'indisponibilité :")
      end

      it "alerts with the validation message when the times are missing" do
        expect { post staff_unavailabilities_path, params: { staff_unavailability: { title: "x" } } }.not_to change(StaffUnavailability, :count)
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:alert]).to eq("Failed to create unavailability: Start time This field is required. and End time This field is required.")
      end

      it "alerts with the validation message when the times are not times" do
        expect { post staff_unavailabilities_path, params: payload(utc_start_time: "abc", utc_end_time: "nope") }.not_to change(StaffUnavailability, :count)
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:alert]).to eq("Failed to create unavailability: Start time This field is required. and End time This field is required.")
      end

      it "redirects home with the ParameterMissing message without the nested hash" do
        post staff_unavailabilities_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to match(/staff_unavailability/)
      end

      it "ignores a user_id param from non-admin staff (always creates for self)" do
        post staff_unavailabilities_path, params: payload(user_id: other.id)
        expect(StaffUnavailability.last.user_id).to eq(staff.id)
        expect(flash[:notice]).to eq("Unavailability created.")
      end
    end

    describe "update" do
      let!(:record) { create(:staff_unavailability, user: staff, title: "Old", start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16)) }

      it "edits a non-recurring record as a whole when the scope 'this' is posted" do
        expect {
          patch staff_unavailability_path(record), params: payload(title: "New").merge(update_scope: "this")
        }.not_to change(StaffUnavailability, :count)
        expect(flash[:notice]).to eq("Unavailability updated successfully.")
        expect(record.reload).to have_attributes(title: "New", recurrence_rule: nil)
      end

      it "updates a non-recurring record" do
        patch staff_unavailability_path(record), params: payload(title: "New", utc_start_time: "2027-03-02T10:00:00Z", utc_end_time: "2027-03-02T11:00:00Z")
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:notice]).to eq("Unavailability updated successfully.")
        expect(record.reload).to have_attributes(title: "New")
        expect(record.start_time.utc.iso8601).to eq("2027-03-02T10:00:00Z")
      end

      it "opens the failure message in French for a French request" do
        patch staff_unavailability_path(record, locale: "fr"), params: payload(utc_start_time: "2027-03-02T12:00:00Z", utc_end_time: "2027-03-02T11:00:00Z")
        expect(flash[:alert]).to start_with("Impossible de modifier l'indisponibilité :")
      end

      it "reports validation failures" do
        patch staff_unavailability_path(record), params: payload(utc_start_time: "2027-03-02T12:00:00Z", utc_end_time: "2027-03-02T11:00:00Z")
        expect(flash[:alert]).to eq("Failed to update unavailability: Start time must be before the end time")
        expect(record.reload.title).to eq("Old")
      end

      it "refuses to change the event type" do
        patch staff_unavailability_path(record), params: payload(event_type: "shift")
        expect(flash[:alert]).to eq("Cannot change an unavailability to another event type.")
        expect(record.reload.title).to eq("Old")
        patch staff_unavailability_path(record), params: payload(event_type: "unavailability", title: "Same")
        expect(record.reload.title).to eq("Same")
      end

      # A one-hour entry from the first 01:30 of the night the clocks go back: its dialog fields read 01:30 to 02:30,
      # which post as two real hours.
      it "keeps the stored times of a one-off when the dialog sends them as it filled them" do
        first = Time.zone.local(2027, 11, 7, 1, 30)
        night = create(:staff_unavailability, user: staff, title: "Night", start_time: first, end_time: first + 1.hour)
        patch staff_unavailability_path(night), params: payload(title: "Renamed", utc_start_time: "2027-11-07T05:30:00Z",
                                                                utc_end_time: "2027-11-07T07:30:00Z").merge(keep_series_times: "1")

        expect(night.reload).to have_attributes(title: "Renamed", start_time: first, end_time: first + 1.hour)
      end

      it "takes the posted times of a one-off when they were changed" do
        first = Time.zone.local(2027, 11, 7, 1, 30)
        night = create(:staff_unavailability, user: staff, title: "Night", start_time: first, end_time: first + 1.hour)
        patch staff_unavailability_path(night), params: payload(utc_start_time: "2027-11-07T05:30:00Z", utc_end_time: "2027-11-07T07:30:00Z")

        expect(night.reload).to have_attributes(start_time: first, end_time: first + 2.hours)
      end

      it "404s for someone else's record and leaves it untouched" do
        theirs = create(:staff_unavailability, user: other, title: "Theirs")
        patch staff_unavailability_path(theirs), params: payload(title: "Hacked")
        expect(response).to have_http_status(:not_found)
        expect(theirs.reload.title).to eq("Theirs")
      end

      context "recurring" do
        let!(:series) { create(:staff_unavailability, user: staff, title: "Series", recurrence_rule: RULE, start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16)) }

        it "scope 'this' excludes the occurrence and creates a one-off record" do
          expect {
            patch staff_unavailability_path(series), params: payload(title: "Once", utc_start_time: "2027-03-22T18:00:00Z", utc_end_time: "2027-03-22T19:00:00Z").merge(update_scope: "this")
          }.to change(StaffUnavailability, :count).by(1)
          expect(flash[:notice]).to eq("This occurrence updated successfully.")
          # the series is at 10:00 Toronto time: 14:00Z once daylight time starts
          expect(series.reload.recurrence_rule).to eq("#{RULE}\nEXDATE:20270322T140000Z")
          once = StaffUnavailability.last
          expect(once).to have_attributes(title: "Once", recurrence_rule: nil, user_id: staff.id)
          expect(once.start_time.utc.iso8601).to eq("2027-03-22T18:00:00Z")
        end

        it "scope 'all' keeps the series date and moves the Toronto time of day" do
          # 18:30Z on 2027-03-22 is 14:30 daylight time; 14:30 on 2027-03-01 is 19:30Z
          patch staff_unavailability_path(series), params: payload(title: "Shifted", utc_start_time: "2027-03-22T18:30:00Z", utc_end_time: "2027-03-22T19:30:00Z", recurrence_rule: "DTSTART:20270322T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO").merge(update_scope: "all")
          expect(flash[:notice]).to eq("All occurrences updated successfully.")
          series.reload
          expect(series.title).to eq("Shifted")
          expect(series.start_time.utc.iso8601).to eq("2027-03-01T19:30:00Z")
          expect(series.end_time.utc.iso8601).to eq("2027-03-01T20:30:00Z")
          expect(series.recurrence_rule).to eq("DTSTART;TZID=America/Toronto:20270301T143000\nRRULE:FREQ=WEEKLY;BYDAY=MO")
        end

        # The dialog sends keep_series_times when its time fields are as it filled them from the clicked occurrence:
        # the series then keeps its own start and length, even where that occurrence's times differ from the series'.
        {
          "the 03:30 occurrence of the day the clocks go forward (a 02:30 series)" =>
            { first: [2027, 3, 7, 2, 30], posted: %w[2027-03-14T07:30:00Z 2027-03-14T08:30:00Z], start_line: "20270307T023000" },
          "the 01:30 occurrence of the night the clocks go back (posted 01:30 to 02:30, two real hours)" =>
            { first: [2027, 10, 31, 1, 30], posted: %w[2027-11-07T05:30:00Z 2027-11-07T07:30:00Z], start_line: "20271031T013000" }
        }.each do |label, c|
          it "scope 'all' with the times left as filled from #{label} keeps the series' start and length" do
            first = Time.zone.local(*c[:first])
            weekly = create(:staff_unavailability, user: staff, title: "Series", start_time: first, end_time: first + 1.hour,
                                                   recurrence_rule: "DTSTART:#{first.utc.strftime('%Y%m%dT%H%M%SZ')}\nRRULE:FREQ=WEEKLY;BYDAY=SU")
            posted_rule = "DTSTART;TZID=America/Toronto:#{Time.iso8601(c[:posted].first).in_time_zone(RecurrenceRule::ZONE).strftime('%Y%m%dT%H%M%S')}\nRRULE:FREQ=WEEKLY;BYDAY=SU"
            patch staff_unavailability_path(weekly), params: payload(title: "Renamed", utc_start_time: c[:posted].first, utc_end_time: c[:posted].last,
                                                                     recurrence_rule: posted_rule).merge(update_scope: "all", keep_series_times: "1")

            expect(weekly.reload).to have_attributes(title: "Renamed", start_time: first, end_time: first + 1.hour,
                                                     recurrence_rule: "DTSTART;TZID=America/Toronto:#{c[:start_line]}\nRRULE:FREQ=WEEKLY;BYDAY=SU")
          end
        end

        it "scope 'all' with a rule that does not validate flashes an alert and changes nothing" do
          patch staff_unavailability_path(series), params: payload(title: "Shifted", recurrence_rule: "DTSTART:20270322T183000Z\nRRULE:FREQ=MINUTELY").merge(update_scope: "all")
          expect(flash[:alert]).to start_with("Failed to update unavailability:")
          expect(series.reload).to have_attributes(title: "Series", recurrence_rule: RULE)
        end

        it "times that are not times flash an alert and change nothing, whatever the scope" do
          before_count = StaffUnavailability.count
          %w[non-recurring all this].each do |scope|
            patch staff_unavailability_path(series), params: payload(title: "Zzz", utc_start_time: "abc", utc_end_time: "2027-03-22T19:00:00Z").merge(update_scope: scope)
            expect(response).to redirect_to(staff_unavailabilities_path), scope
            expect(flash[:alert]).to eq("Failed to update unavailability: Start time This field is required."), scope
          end
          expect(series.reload).to have_attributes(title: "Series", recurrence_rule: RULE)
          expect(StaffUnavailability.count).to eq(before_count)
        end

        it "an unknown scope flashes an alert and changes nothing" do
          patch staff_unavailability_path(series), params: payload(title: "Zzz").merge(update_scope: "bogus")
          expect(flash[:alert]).to eq("Invalid update scope.")
          expect(series.reload.title).to eq("Series")
        end

        it "a missing scope on a recurring record is also invalid" do
          patch staff_unavailability_path(series), params: payload(title: "Zzz")
          expect(flash[:alert]).to eq("Invalid update scope.")
        end
      end
    end

    describe "destroy" do
      it "deletes own record" do
        mine = create(:staff_unavailability, user: staff)
        expect { delete staff_unavailability_path(mine) }.to change(StaffUnavailability, :count).by(-1)
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:notice]).to eq("Unavailability deleted.")
      end

      it "404s for someone else's record" do
        theirs = create(:staff_unavailability, user: other)
        expect { delete staff_unavailability_path(theirs) }.not_to change(StaffUnavailability, :count)
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "delete_with_scope" do
      let!(:series) { create(:staff_unavailability, user: staff, recurrence_rule: RULE, start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16)) }

      it "destroys a non-recurring record whatever the scope" do
        plain = create(:staff_unavailability, user: staff)
        expect { delete delete_with_scope_staff_unavailability_path(plain), params: { scope: "bogus" } }.to change(StaffUnavailability, :count).by(-1)
        expect(flash[:notice]).to eq("Unavailability deleted.")
      end

      it "single adds an EXDATE" do
        delete delete_with_scope_staff_unavailability_path(series), params: { scope: "single", start_date: "2027-03-08T15:00:00Z" }
        expect(flash[:notice]).to eq("This occurrence deleted.")
        expect(series.reload.recurrence_rule).to eq("#{RULE_AS_WRITTEN}\nEXDATE:20270308T150000Z")
      end

      it "following ends the series the day before the chosen start" do
        delete delete_with_scope_staff_unavailability_path(series), params: { scope: "following", start_date: "2027-03-15T15:00:00Z" }
        expect(flash[:notice]).to eq("This and following deleted.")
        expect(series.reload.recurrence_rule).to eq("DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20270314T150000Z")
      end

      it "following replaces an existing UNTIL" do
        series.update!(recurrence_rule: "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20271201T000000Z")
        delete delete_with_scope_staff_unavailability_path(series), params: { scope: "following", start_date: "2027-03-15T15:00:00Z" }
        expect(series.reload.recurrence_rule).to include("UNTIL=20270314T150000Z")
        expect(series.recurrence_rule).not_to include("20271201")
      end

      it "refuses a start_date that is not a time like a missing one and leaves the series as it was" do
        { "single" => "a single occurrence", "following" => "following occurrences" }.each do |scope, words|
          delete delete_with_scope_staff_unavailability_path(series), params: { scope: scope, start_date: "not a date" }
          expect(response).to redirect_to(staff_unavailabilities_path), scope
          expect(flash[:alert]).to eq("Start date is required for deleting #{words}."), scope
        end
        expect(series.reload.recurrence_rule).to eq(RULE)
      end

      it "reads a start_date with an offset as its instant" do
        delete delete_with_scope_staff_unavailability_path(series), params: { scope: "single", start_date: "2027-03-08T10:00:00-05:00" }
        expect(series.reload.recurrence_rule).to eq("#{RULE_AS_WRITTEN}\nEXDATE:20270308T150000Z")
      end

      it "all destroys the series" do
        expect { delete delete_with_scope_staff_unavailability_path(series), params: { scope: "all" } }.to change(StaffUnavailability, :count).by(-1)
        expect(flash[:notice]).to eq("All occurrences deleted.")
      end

      it "requires start_date for single/following and rejects unknown scopes" do
        delete delete_with_scope_staff_unavailability_path(series), params: { scope: "single" }
        expect(flash[:alert]).to eq("Start date is required for deleting a single occurrence.")
        delete delete_with_scope_staff_unavailability_path(series), params: { scope: "following" }
        expect(flash[:alert]).to eq("Start date is required for deleting following occurrences.")
        delete delete_with_scope_staff_unavailability_path(series), params: { scope: "bogus" }
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:alert]).to eq("Invalid delete scope: bogus")
        expect(series.reload.recurrence_rule).to eq(RULE)
      end

      it "404s for someone else's record" do
        theirs = create(:staff_unavailability, user: other)
        delete delete_with_scope_staff_unavailability_path(theirs), params: { scope: "all" }
        expect(response).to have_http_status(:not_found)
        expect(StaffUnavailability.exists?(theirs.id)).to be(true)
      end
    end

    describe "json feed" do
      # The feed sends the occurrences in the range the calendar asks for (?start&end).
      def get_feed(from: Time.current, to: from + 7.days)
        get json_staff_unavailabilities_path, params: { start: from.iso8601, end: to.iso8601 }
      end

      it "returns only the user's own records with the FullCalendar shape, in Toronto offsets" do
        create(:staff_unavailability, user: other, title: "Not mine")
        single = create(:staff_unavailability, user: staff, title: "Once", description: "d",
                                               start_time: Time.utc(2027, 3, 14, 6, 30), end_time: Time.utc(2027, 3, 14, 7, 30))
        get_feed(from: Time.utc(2027, 3, 13))
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([{
          "id" => single.id, "title" => "Once",
          "start" => "2027-03-14T01:30:00-05:00", "end" => "2027-03-14T03:30:00-04:00", # across the DST jump
          "allDay" => false,
          "extendedProps" => { "description" => "d", "eventType" => "unavailability", "userId" => staff.id, "isAdminCreated" => false,
                               "recordId" => single.id, "series" => nil, "occurrenceStart" => "2027-03-14T06:30:00Z" }
        }])
      end

      it "names an entry without a title Unavailable, not made by an admin" do
        create(:staff_unavailability, user: staff, title: nil, start_time: Time.utc(2027, 3, 14, 14), end_time: Time.utc(2027, 3, 14, 15))
        get_feed(from: Time.utc(2027, 3, 13))
        row = response.parsed_body.sole
        expect([row["title"], row.dig("extendedProps", "isAdminCreated")]).to eq(["Unavailable", nil])
      end

      it "leaves out the records outside the range" do
        create(:staff_unavailability, user: staff, title: "Later", start_time: Time.utc(2027, 4, 14, 14), end_time: Time.utc(2027, 4, 14, 15))
        get_feed(from: Time.utc(2027, 3, 13))
        expect(response.parsed_body).to eq([])
      end

      it "answers 400 with the reason when the range is missing" do
        get json_staff_unavailabilities_path
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to eq("error" => I18n.t("errors.calendar.window_invalid"))
      end

      it "sends each occurrence of a series in the range at its Toronto clock time, without the excluded ones" do
        rule = "#{RULE}\nEXDATE:20270308T150000Z\nEXDATE:20270329T150000Z"
        record = create(:staff_unavailability, user: staff, recurrence_rule: rule, start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16))
        get_feed(from: Time.utc(2027, 3, 1), to: Time.utc(2027, 4, 1))
        rows = response.parsed_body
        # 2027-03-29 10:00 daylight time is 14:00Z, so the exclusion stamped 15:00Z does not remove it
        expect(rows.map { |row| [row["id"], row["start"], row["end"]] }).to eq([
          ["#{record.id}@#{Time.utc(2027, 3, 1, 15).to_i}", "2027-03-01T10:00:00-05:00", "2027-03-01T11:00:00-05:00"],
          ["#{record.id}@#{Time.utc(2027, 3, 15, 14).to_i}", "2027-03-15T10:00:00-04:00", "2027-03-15T11:00:00-04:00"],
          ["#{record.id}@#{Time.utc(2027, 3, 22, 14).to_i}", "2027-03-22T10:00:00-04:00", "2027-03-22T11:00:00-04:00"],
          ["#{record.id}@#{Time.utc(2027, 3, 29, 14).to_i}", "2027-03-29T10:00:00-04:00", "2027-03-29T11:00:00-04:00"]
        ])
        expect(rows.second["extendedProps"]).to include(
          "recordId" => record.id, "occurrenceStart" => "2027-03-15T14:00:00Z",
          "series" => { "frequency" => "WEEKLY", "weekdays" => ["MO"], "until" => nil }
        )
        expect(rows).to all(satisfy { |row| !row.key?("rrule") && !row.key?("duration") })
      end

      it "sends the Toronto date a series repeats until" do
        create(:staff_unavailability, user: staff, recurrence_rule: "#{RULE};UNTIL=20270316T035959Z",
                                      start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16))
        get_feed(from: Time.utc(2027, 3, 1), to: Time.utc(2027, 4, 1))
        expect(response.parsed_body.map { |row| row["start"] }).to eq(%w[2027-03-01T10:00:00-05:00 2027-03-08T10:00:00-05:00 2027-03-15T10:00:00-04:00])
        expect(response.parsed_body.first.dig("extendedProps", "series", "until")).to eq("2027-03-15")
      end

      it "sends an occurrence that began before the range and reaches into it" do
        record = create(:staff_unavailability, user: staff, recurrence_rule: "RRULE:FREQ=DAILY",
                                               start_time: Time.utc(2027, 3, 1, 3), end_time: Time.utc(2027, 3, 1, 7))
        get_feed(from: Time.utc(2027, 3, 3, 5), to: Time.utc(2027, 3, 3, 6))
        expect(response.parsed_body.map { |row| row["id"] }).to eq(["#{record.id}@#{Time.utc(2027, 3, 3, 3).to_i}"])
      end

      it "still lists a series whose stored start line cannot be read, from its own start" do
        record = create(:staff_unavailability, user: staff, start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16))
        record.update_column(:recurrence_rule, "DTSTART;TZID=Nowhere/Land:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO")
        get_feed(from: Time.utc(2027, 3, 1))
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |row| row["start"] }).to eq(["2027-03-01T10:00:00-05:00"])
      end

      it "flags all-day (exactly 24h) records, sent as dates, and admin-created titles" do
        create(:staff_unavailability, user: staff, title: "Away (Admin)", start_time: Time.utc(2027, 3, 1, 5), end_time: Time.utc(2027, 3, 2, 5))
        get_feed(from: Time.utc(2027, 3, 1))
        row = response.parsed_body.first
        expect(row.values_at("allDay", "start", "end")).to eq([true, "2027-03-01", "2027-03-02"])
        expect(row["extendedProps"]["isAdminCreated"]).to be(true)
      end

      it "merges external ICS feeds (HTTP stubbed) prefixed with 'External - '" do
        url = "https://cal.test/ext.ics"
        StaffExternalUnavailability.create!(user: staff, ics_url: url)
        stub_ics(url, body: ics_document(uid: "e1", summary: "Dentist", start: 3.days.from_now, end: 3.days.from_now + 1.hour))
        get_feed
        titles = response.parsed_body.map { |r| r["title"] }
        expect(titles).to eq(["External - Dentist"])
        expect(response.parsed_body.first["extendedProps"]["name"]).to eq("#{staff.name} External Unavailability")
        expect(response.parsed_body.first["extendedProps"]).not_to have_key("eventType")
      end

      it "names the host of the link an external event came from, never the link itself" do
        url = "https://calendar.example.org/private/secret-token-123/basic.ics?key=abc"
        StaffExternalUnavailability.create!(user: staff, ics_url: url)
        stub_ics(url, body: ics_document(uid: "e2", summary: "Dentist", start: 3.days.from_now, end: 3.days.from_now + 1.hour))
        get_feed
        expect(response.parsed_body.first["extendedProps"]["sourceHost"]).to eq("calendar.example.org")
        expect(response.body).not_to include("secret-token-123")
        expect(response.body).not_to include("key=abc")
      end

      it "names the host of each linked calendar that could not be loaded in a header, never the link" do
        down = "https://down.example.org/private/secret-down/basic.ics?key=zzz"
        slow = "https://slow.example.org/private/secret-slow/basic.ics"
        empty = "https://empty.example.org/private/secret-empty/basic.ics"
        [down, slow, empty].each { |url| StaffExternalUnavailability.create!(user: staff, ics_url: url) }
        stub_ics(down, status: 503)
        stub_request(:get, slow).to_timeout
        stub_ics(empty, body: ics_document)
        get_feed

        expect(JSON.parse(response.headers["X-Failed-Calendars"])).to contain_exactly("down.example.org", "slow.example.org")
        expect(response.parsed_body).to eq([])
        expect(response.body + response.headers.to_h.to_s).not_to match(/secret-|key=zzz/)
      end

      it "reports a link that answers 200 with something that is not a calendar, but not a valid empty calendar" do
        page = "https://login.example.org/private/secret-login/basic.ics"
        valid = "https://valid.example.org/basic.ics"
        [page, valid].each { |url| StaffExternalUnavailability.create!(user: staff, ics_url: url) }
        stub_request(:get, page).to_return(status: 200, body: "<html><body>Please sign in</body></html>")
        stub_ics(valid, body: ics_document)
        get_feed

        expect(JSON.parse(response.headers["X-Failed-Calendars"])).to eq(["login.example.org"])
      end

      it "still reports a failed link whose host cannot be read, without a name" do
        StaffExternalUnavailability.new(user: staff, ics_url: "https://exa mple.org/a.ics").save!(validate: false)
        get_feed

        expect(JSON.parse(response.headers["X-Failed-Calendars"])).to eq([nil])
      end

      it "tells the browser not to reuse an earlier answer, since the failure header is not part of the body's ETag" do
        get_feed
        expect(response.headers["Cache-Control"]).to eq("no-store")
      end

      it "sends no failure header when every linked calendar loads" do
        url = "https://cal.test/fine.ics"
        StaffExternalUnavailability.create!(user: staff, ics_url: url)
        stub_ics(url, body: ics_document)
        get_feed
        expect(response.headers).not_to have_key("X-Failed-Calendars")
      end

      it "silently drops an external feed that fails to download" do
        url = "https://cal.test/down.ics"
        StaffExternalUnavailability.create!(user: staff, ics_url: url)
        stub_ics(url, status: 503)
        get_feed
        expect(response.parsed_body).to eq([])
      end
    end

    describe "update_external_unavailabilities" do
      it "replaces the user's links and leaves other users' links alone" do
        StaffExternalUnavailability.create!(user: staff, ics_url: "https://old.test/a.ics")
        theirs = StaffExternalUnavailability.create!(user: other, ics_url: "https://other.test/a.ics")
        patch update_external_unavailabilities_staff_unavailabilities_path, params: { external_calendar: ["https://new.test/a.ics", "", "https://new.test/b.ics"] }
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:notice]).to eq("External calendar links updated.")
        expect(StaffExternalUnavailability.where(user: staff).pluck(:ics_url)).to match_array(%w[https://new.test/a.ics https://new.test/b.ics])
        expect(StaffExternalUnavailability.exists?(theirs.id)).to be(true)
      end

      it "accepts a scalar param and clears all links when none are sent" do
        patch update_external_unavailabilities_staff_unavailabilities_path, params: { external_calendar: "https://one.test/a.ics" }
        expect(StaffExternalUnavailability.where(user: staff).pluck(:ics_url)).to eq(["https://one.test/a.ics"])
        patch update_external_unavailabilities_staff_unavailabilities_path
        expect(StaffExternalUnavailability.where(user: staff)).to be_empty
        expect(flash[:notice]).to eq("External calendar links updated.")
      end

      it "refuses a link that is not http or https and leaves the saved links as they were" do
        StaffExternalUnavailability.create!(user: staff, ics_url: "https://keep.test/a.ics")
        ["not a url", "file:///etc/passwd", "ftp://x.test/a.ics", "https://u:p@x.test/a.ics", "https://x.test:8080/a.ics"].each do |bad|
          patch update_external_unavailabilities_staff_unavailabilities_path, params: { external_calendar: ["https://new.test/a.ics", bad] }
          expect(response).to redirect_to(staff_unavailabilities_path)
          expect(flash[:alert]).to include("is not an http or https link")
          expect(StaffExternalUnavailability.where(user: staff).pluck(:ics_url)).to eq(["https://keep.test/a.ics"])
        end
      end
    end
  end

  context "as admin" do
    let!(:admin) { sign_in_as(:admin) }
    let(:staffer) { create(:user, :staff) }

    it "creates for another user, flagged '(Admin)', and returns to the admin calendar" do
      post staff_unavailabilities_path, params: payload(title: "", user_id: staffer.id)
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(flash[:notice]).to eq("Unavailability created for #{staffer.name}.")
      expect(StaffUnavailability.last).to have_attributes(user_id: staffer.id, title: "Unavailable (Admin)")
    end

    it "creates for self when user_id is the admin's own id (staff path)" do
      post staff_unavailabilities_path, params: payload(user_id: admin.id)
      expect(response).to redirect_to(staff_unavailabilities_path)
      expect(StaffUnavailability.last.user_id).to eq(admin.id)
    end

    it "returns to the admin calendar when the referer is an admin page" do
      post staff_unavailabilities_path, params: payload, headers: { "HTTP_REFERER" => admin_calendar_index_url }
      expect(response).to redirect_to(admin_calendar_index_path)
    end

    it "edits and deletes other users' records (no ownership restriction for admins)" do
      theirs = create(:staff_unavailability, user: staffer, title: "Theirs")
      patch staff_unavailability_path(theirs), params: payload(title: "Edited")
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(theirs.reload.title).to eq("Edited")
      delete staff_unavailability_path(theirs)
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(StaffUnavailability.exists?(theirs.id)).to be(false)
    end

    it "json only lists the admin's own unavailabilities" do
      create(:staff_unavailability, user: staffer)
      get json_staff_unavailabilities_path, params: { start: Time.current.iso8601, end: 7.days.from_now.iso8601 }
      expect(response.parsed_body).to eq([])
    end
  end
end
