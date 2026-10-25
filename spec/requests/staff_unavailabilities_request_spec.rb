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
        expect(response.location).to start_with("http://www.example.com/login?back_to="), name.to_s
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
        expect { post staff_unavailabilities_path, params: payload(recurrence_rule: "FREQ=WEEKLY") }.not_to change(StaffUnavailability, :count)
        expect(flash[:alert]).to eq("Failed to create unavailability: Recurrence rule must include days of the week when using weekly frequency")
      end

      # WART(D-SP13): missing times raise TypeError from Time.parse(nil) (500) instead of a validation alert.
      it "500s when the times are missing" do
        post staff_unavailabilities_path, params: { staff_unavailability: { title: "x" } }
        expect(response).to have_http_status(:internal_server_error)
        expect(StaffUnavailability.count).to eq(0)
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

      it "updates a non-recurring record" do
        patch staff_unavailability_path(record), params: payload(title: "New", utc_start_time: "2027-03-02T10:00:00Z", utc_end_time: "2027-03-02T11:00:00Z")
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:notice]).to eq("Unavailability updated successfully.")
        expect(record.reload).to have_attributes(title: "New")
        expect(record.start_time.utc.iso8601).to eq("2027-03-02T10:00:00Z")
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
          expect(series.reload.recurrence_rule).to eq("#{RULE}\nEXDATE:20270322T150000Z")
          once = StaffUnavailability.last
          expect(once).to have_attributes(title: "Once", recurrence_rule: nil, user_id: staff.id)
          expect(once.start_time.utc.iso8601).to eq("2027-03-22T18:00:00Z")
        end

        it "scope 'all' keeps the series date and moves the time of day" do
          patch staff_unavailability_path(series), params: payload(title: "Shifted", utc_start_time: "2027-03-22T18:30:00Z", utc_end_time: "2027-03-22T19:30:00Z", recurrence_rule: "DTSTART:20270322T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO").merge(update_scope: "all")
          expect(flash[:notice]).to eq("All occurrences updated successfully.")
          series.reload
          expect(series.title).to eq("Shifted")
          expect(series.start_time.utc.iso8601).to eq("2027-03-01T18:30:00Z")
          expect(series.end_time.utc.iso8601).to eq("2027-03-01T19:30:00Z")
          expect(series.recurrence_rule).to eq("DTSTART:20270301T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO")
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
        expect(series.reload.recurrence_rule).to eq("#{RULE}\nEXDATE:20270308T150000Z")
      end

      it "following ends the series the day before the chosen start" do
        delete delete_with_scope_staff_unavailability_path(series), params: { scope: "following", start_date: "2027-03-15T15:00:00Z" }
        expect(flash[:notice]).to eq("This and following deleted.")
        expect(series.reload.recurrence_rule).to eq("DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20270314T150000Z")
      end

      it "following replaces an existing UNTIL" do
        series.update!(recurrence_rule: "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20271201T000000Z")
        delete delete_with_scope_staff_unavailability_path(series), params: { scope: "following", start_date: "2027-03-15T15:00:00Z" }
        expect(series.reload.recurrence_rule).to include("UNTIL=20270314T150000Z")
        expect(series.recurrence_rule).not_to include("20271201")
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
      it "returns only the user's own records with the FullCalendar shape, in Toronto offsets" do
        create(:staff_unavailability, user: other, title: "Not mine")
        single = create(:staff_unavailability, user: staff, title: "Once", description: "d",
                                               start_time: Time.utc(2027, 3, 14, 6, 30), end_time: Time.utc(2027, 3, 14, 7, 30))
        get json_staff_unavailabilities_path
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([{
          "id" => single.id, "title" => "Once",
          "start" => "2027-03-14T01:30:00-05:00", "end" => "2027-03-14T03:30:00-04:00", # across the DST jump
          "allDay" => false,
          "extendedProps" => { "description" => "d", "eventType" => "unavailability", "userId" => staff.id, "isAdminCreated" => false }
        }])
      end

      it "adds rrule + duration for recurring records, converting EXDATE to Toronto wall-clock" do
        rule = "#{RULE}\nEXDATE:20270308T150000Z\nEXDATE:20270329T150000Z"
        create(:staff_unavailability, user: staff, recurrence_rule: rule, start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16))
        get json_staff_unavailabilities_path
        row = response.parsed_body.first
        expect(row["duration"]).to eq(3_600_000.0)
        expect(row["rrule"]).to eq("DTSTART:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T100000\nEXDATE:20270329T110000")
      end

      it "flags all-day (exactly 24h) records and admin-created titles" do
        create(:staff_unavailability, user: staff, title: "Away (Admin)", start_time: Time.utc(2027, 3, 1, 5), end_time: Time.utc(2027, 3, 2, 5))
        get json_staff_unavailabilities_path
        row = response.parsed_body.first
        expect(row["allDay"]).to be(true)
        expect(row["extendedProps"]["isAdminCreated"]).to be(true)
      end

      it "merges external ICS feeds (HTTP stubbed) prefixed with 'External - '" do
        url = "https://cal.test/ext.ics"
        StaffExternalUnavailability.create!(user: staff, ics_url: url)
        stub_ics(url, body: ics_document(uid: "e1", summary: "Dentist", start: 3.days.from_now, end: 3.days.from_now + 1.hour))
        get json_staff_unavailabilities_path
        titles = response.parsed_body.map { |r| r["title"] }
        expect(titles).to eq(["External - Dentist"])
        expect(response.parsed_body.first["extendedProps"]["name"]).to eq("#{staff.name} External Unavailability")
      end

      it "silently drops an external feed that fails to download" do
        url = "https://cal.test/down.ics"
        StaffExternalUnavailability.create!(user: staff, ics_url: url)
        stub_ics(url, status: 503)
        get json_staff_unavailabilities_path
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

      # WART(D-SP14): the destroy_all runs before anything is validated and links are not checked as URLs (any string is stored and later fetched server-side).
      it "stores any string as an ICS url (no URL validation)" do
        patch update_external_unavailabilities_staff_unavailabilities_path, params: { external_calendar: ["not a url"] }
        expect(StaffExternalUnavailability.where(user: staff).pluck(:ics_url)).to eq(["not a url"])
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
      # WART(D-SP15): update never sets @unavailability, so admin_managing_other_user? is false and the redirect goes to the staff page (destroy goes to the admin calendar).
      patch staff_unavailability_path(theirs), params: payload(title: "Edited")
      expect(response).to redirect_to(staff_unavailabilities_path)
      expect(theirs.reload.title).to eq("Edited")
      delete staff_unavailability_path(theirs)
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(StaffUnavailability.exists?(theirs.id)).to be(false)
    end

    it "json only lists the admin's own unavailabilities" do
      create(:staff_unavailability, user: staffer)
      get json_staff_unavailabilities_path
      expect(response.parsed_body).to eq([])
    end
  end
end
