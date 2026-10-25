# frozen_string_literal: true

require "rails_helper"

# Chunk 11 gap-closer for Admin::EventsController: the non-admin matrix, create
# branches, update scopes (non-recurring / all / this / invalid), delete scopes,
# json shape corners, publish / delete_drafts failure paths and copy.
#
# Fixtures use fixed UTC instants. The controller parses the posted strings with
# `Time.parse(...).utc` (container TZ, UTC in the devcontainer and CI), so the
# strings below are UTC walls.

RSpec.describe "Admin events gaps", type: :request do
  let(:space) { create(:space) }
  let(:admin) { create(:user, :admin, booking_approval: true) }
  # a weekly Monday series starting 2025-05-05 15:00 UTC (1 hour long)
  let(:series_rule) { "DTSTART:20250505T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=5" }
  let(:series) do
    create(:event, space: space, title: "Series", created_by: create(:user, :staff),
                   start_time: Time.utc(2025, 5, 5, 15, 0), end_time: Time.utc(2025, 5, 5, 16, 0),
                   recurrence_rule: series_rule)
  end

  def log_in!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  def event_attrs(overrides = {})
    { event_type: "meeting", title: "Titled", description: "Desc", space_id: space.id,
      utc_start_time: "2027-04-01 10:00", utc_end_time: "2027-04-01 11:00" }.merge(overrides)
  end

  # ---------------------------------------------------------------- role matrix

  describe "non-admin callers (AdminAreaController#ensure_admin)" do
    let!(:event) { create(:event, space: space, title: "Untouched") }
    let!(:draft) { create(:event, :draft, space: space, title: "DraftUntouched") }

    {
      guest: nil,
      regular: :regular_user,
      staff: :staff
    }.each do |role, trait|
      context "as a #{role}" do
        before { log_in!(create(:user, trait, booking_approval: true)) if trait }

        it "bounces create, update, delete_with_scope, publish, delete_drafts and copy to / and changes nothing" do
          post admin_events_path, params: { event: event_attrs(title: "Intruder") }
          expect(response).to redirect_to("/")

          patch admin_event_path(event), params: { event: event_attrs(title: "Hacked") }
          expect(response).to redirect_to("/")

          delete delete_with_scope_admin_event_path(event)
          expect(response).to redirect_to("/")

          patch publish_admin_event_path(draft)
          expect(response).to redirect_to("/")

          delete delete_drafts_admin_events_path, params: { space_id: space.id,
                                                            view_start_date: "2000-01-01",
                                                            view_end_date: "2100-01-01" }
          expect(response).to redirect_to("/")

          post copy_admin_events_path, params: { space_id: space.id }
          expect(response).to redirect_to("/")

          expect(Event.where(title: "Intruder")).to be_empty
          expect(event.reload.title).to eq("Untouched")
          expect(Event.exists?(event.id)).to be(true)
          expect(draft.reload.draft).to be(true)
          expect(Event.exists?(draft.id)).to be(true)
        end

        it "bounces the json feed to /" do
          get json_admin_events_path(id: space.id)
          expect(response).to redirect_to("/")
        end
      end
    end
  end

  # ---------------------------------------------------------------- create

  describe "POST create" do
    before { log_in!(admin) }

    it "keeps an explicit title" do
      post admin_events_path, params: { event: event_attrs(title: "Maker Meetup") }
      expect(flash[:notice]).to eq("Event created successfully.")
      expect(Event.order(:id).last.title).to eq("Maker Meetup")
    end

    it "flashes the validation failure when the space is missing" do
      expect do
        post admin_events_path, params: { event: event_attrs(space_id: "") }
      end.not_to change(Event, :count)
      expect(flash[:alert]).to eq("Failed to create event: Space must exist and Space This field is required.")
    end

    it "flashes the validation failure when the end is not after the start" do
      post admin_events_path, params: { event: event_attrs(utc_end_time: "2027-04-01 10:00") }
      expect(flash[:alert]).to eq("Failed to create event: Start time must be before the end time")
    end

    it "creates one EventAssignment per staff_select entry" do
      staff_a = create(:user, :staff)
      staff_b = create(:user, :staff)
      post admin_events_path, params: { event: event_attrs, staff_select: [staff_a.id, staff_b.id] }
      created = Event.order(:id).last
      expect(created.event_assignments.pluck(:user_id)).to match_array([staff_a.id, staff_b.id])
    end

    it "saves a training event without a training as a draft (the training rule only applies once published)" do
      post admin_events_path, params: { event: event_attrs(event_type: "training") }
      created = Event.order(:id).last
      expect(flash[:notice]).to eq("Event created successfully.")
      expect(created.event_type).to eq("training")
      expect(created.training_id).to be_nil
      expect(created.draft).to be(true)
    end

    it "does not push a draft to Google Calendar" do
      post admin_events_path, params: { event: event_attrs }
      expect(Event).not_to have_received(:upsert_event)
    end

    # WART(D-B46): Time.parse(nil) raises TypeError before any validation
    it "answers 500 (TypeError) when the utc_* params are missing" do
      post admin_events_path, params: { event: event_attrs.except(:utc_start_time, :utc_end_time) }
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("TypeError")
    end
  end

  # ---------------------------------------------------------------- update

  describe "PATCH update" do
    before { log_in!(admin) }

    it "flashes the validation failure of a non-recurring update and keeps the record" do
      event = create(:event, space: space, title: "Keep")
      patch admin_event_path(event),
            params: { event: event_attrs(utc_end_time: "2027-04-01 09:00") }
      expect(flash[:alert]).to eq("Failed to update event: Start time must be before the end time")
      expect(event.reload.title).to eq("Keep")
    end

    it "replaces the assignments with the submitted staff_select list" do
      old_staff = create(:user, :staff)
      new_staff = create(:user, :staff)
      event = create(:event, space: space)
      create(:event_assignment, event: event, user: old_staff)

      patch admin_event_path(event), params: { event: event_attrs, staff_select: [new_staff.id] }
      expect(event.reload.event_assignments.pluck(:user_id)).to eq([new_staff.id])

      patch admin_event_path(event), params: { event: event_attrs }
      expect(event.reload.event_assignments).to be_empty
    end

    it "falls back to the capitalized event_type when the title is blanked" do
      event = create(:event, space: space, title: "Named")
      patch admin_event_path(event), params: { event: event_attrs(title: "  ") }
      expect(event.reload.title).to eq("Meeting")
    end

    it "answers 404 for an unknown event" do
      patch admin_event_path(id: 99_999_999), params: { event: event_attrs }
      expect(response).to have_http_status(:not_found)
    end

    it "pushes a published event to Google Calendar after updating" do
      event = create(:event, space: space)
      patch admin_event_path(event), params: { event: event_attrs }
      # WART(D-B45): the before_save callback AND the controller both upsert
      expect(Event).to have_received(:upsert_event).with(event).at_least(:twice)
    end

    context "recurring event, scope 'all'" do
      # The time of day of the rewritten DTSTART comes from the DTSTART line of
      # the POSTED rule (the calendar UI sends it in sync with utc_start_time).
      it "moves the whole series to the new time of day, keeps the series date and the rule, and wrongly flashes 'Unavailability'" do
        # WART(D-B43): the success flash says "Unavailability updated"; the scope
        # also leaves created_by_id and space_id alone.
        patch admin_event_path(series),
              params: { update_scope: "all",
                        event: event_attrs(utc_start_time: "2027-04-01 16:30",
                                           utc_end_time: "2027-04-01 17:45",
                                           recurrence_rule: "DTSTART:20270401T163000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=5",
                                           title: "Series v2") }

        expect(flash[:notice]).to eq("Unavailability updated successfully.")
        series.reload
        expect(series.title).to eq("Series v2")
        expect(series.start_time).to eq(Time.utc(2025, 5, 5, 16, 30))
        expect(series.end_time).to eq(Time.utc(2025, 5, 5, 17, 45))
        expect(series.recurrence_rule).to eq("DTSTART:20250505T163000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=5")
        expect(series.created_by.role).to eq("staff")
        expect(series.space_id).to eq(space.id)
      end

      it "stores the submitted rule verbatim when the frequency changed" do
        new_rule = "DTSTART:20270401T160000Z\nRRULE:FREQ=WEEKLY;BYDAY=TH;COUNT=3"
        patch admin_event_path(series),
              params: { update_scope: "all",
                        event: event_attrs(recurrence_rule: new_rule) }
        expect(series.reload.recurrence_rule).to eq(new_rule)
      end
    end

    context "recurring event, scope 'this'" do
      it "excludes the occurrence from the series and creates a standalone replacement event" do
        series # create the master first
        expect do
          patch admin_event_path(series),
                params: { update_scope: "this",
                          event: event_attrs(utc_start_time: "2025-05-12 17:00",
                                             utc_end_time: "2025-05-12 18:00",
                                             title: "Moved occurrence") }
        end.to change(Event, :count).by(1)

        expect(flash[:notice]).to eq("This event occurrence updated successfully.")
        expect(series.reload.recurrence_rule).to eq("#{series_rule}\nEXDATE:20250512T150000Z")
        replacement = Event.order(:id).last
        expect(replacement.title).to eq("Moved occurrence")
        expect(replacement.recurrence_rule).to be_nil
        expect(replacement.start_time).to eq(Time.utc(2025, 5, 12, 17, 0))
        expect(replacement.end_time).to eq(Time.utc(2025, 5, 12, 18, 0))
        expect(replacement.created_by_id).to eq(admin.id)
      end

      it "assigns the submitted staff to the replacement event only" do
        staff = create(:user, :staff)
        patch admin_event_path(series),
              params: { update_scope: "this", staff_select: [staff.id],
                        event: event_attrs(utc_start_time: "2025-05-12 17:00",
                                           utc_end_time: "2025-05-12 18:00") }
        expect(Event.order(:id).last.event_assignments.pluck(:user_id)).to eq([staff.id])
        expect(series.reload.event_assignments).to be_empty
      end

      # WART(D-B44): the master already carries the EXDATE when Event.create! raises
      it "leaves the master modified and answers 422 (unhandled RecordInvalid) when the replacement is invalid" do
        patch admin_event_path(series),
              params: { update_scope: "this",
                        event: event_attrs(utc_start_time: "2025-05-12 18:00",
                                           utc_end_time: "2025-05-12 17:00") }
        expect(response).to have_http_status(:unprocessable_content)
        expect(series.reload.recurrence_rule).to end_with("EXDATE:20250512T150000Z")
        expect(Event.count).to eq(1)
      end
    end

    it "flashes an error for an unknown update scope on a recurring event" do
      patch admin_event_path(series), params: { update_scope: "bogus", event: event_attrs }
      expect(flash[:alert]).to eq("Invalid update scope.")
      expect(series.reload.title).to eq("Series")
    end
  end

  # ---------------------------------------------------------------- delete scopes

  describe "DELETE delete_with_scope on a recurring event" do
    before { log_in!(admin) }

    it "single: appends an EXDATE for the chosen occurrence and keeps the series" do
      delete delete_with_scope_admin_event_path(series),
             params: { scope: "single", start_date: "2025-05-12 15:00" }
      expect(flash[:notice]).to eq("This occurrence deleted.")
      expect(Event.exists?(series.id)).to be(true)
      expect(series.reload.recurrence_rule).to eq(
        "DTSTART:20250505T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=5\nEXDATE:20250512T150000Z"
      )
    end

    it "following: ends the series the day before the chosen occurrence" do
      delete delete_with_scope_admin_event_path(series),
             params: { scope: "following", start_date: "2025-05-19 15:00" }
      expect(flash[:notice]).to eq("This and following deleted.")
      expect(series.reload.recurrence_rule).to eq(
        "DTSTART:20250505T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=5;UNTIL=20250518T150000Z"
      )
    end

    it "following: needs a start_date" do
      delete delete_with_scope_admin_event_path(series), params: { scope: "following" }
      expect(flash[:alert]).to eq("Start date is required.")
      expect(series.reload.recurrence_rule).to eq(series_rule)
    end
  end

  # ---------------------------------------------------------------- json corners

  describe "GET json corners" do
    before { log_in!(admin) }

    def entries_for(space_id)
      get json_admin_events_path(id: space_id)
      response.parsed_body.flat_map { |group| group["events"] }
    end

    it "renders the grey gradient and an Unassigned user for an event without staff" do
      create(:event, space: space, title: "Solo")
      entry = entries_for(space.id).first
      expect(entry["extendedProps"]["assignedUsers"]).to eq([{ "id" => 0, "name" => "Unassigned" }])
      expect(entry["extendedProps"]["background"])
        .to eq("linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);")
    end

    it "marks drafts with opacity in the gradient" do
      create(:event, :draft, space: space)
      expect(entries_for(space.id).first["extendedProps"]["background"])
        .to eq("linear-gradient(to right, #bbb 0.0%, #bbb 100.0%); opacity: 0.8;")
    end

    it "splits the gradient evenly across assigned staff using their StaffSpace colours" do
      staff_a = create(:user, :staff)
      staff_b = create(:user, :staff)
      colors = {}
      [staff_a, staff_b].each { |u| colors[u.id] = StaffSpace.create!(user: u, space: space, color: "#000000").color }
      event = create(:event, space: space, title: "Duo")
      [staff_a, staff_b].each { |u| create(:event_assignment, event: event, user: u) }

      entry = entries_for(space.id).first
      a, b = colors.values_at(staff_a.id, staff_b.id)
      expect(entry["extendedProps"]["background"])
        .to eq("linear-gradient(to right, #{a} 0.0%, #{a} 50.0%, #{b} 50.0%, #{b} 100.0%);")
      expect(entry["extendedProps"]["assignedUsers"])
        .to eq([{ "id" => staff_a.id, "name" => staff_a.name }, { "id" => staff_b.id, "name" => staff_b.name }])
    end

    it "builds a staffed training title from the training, course and language" do
      staff = create(:user, :staff, name: "Alex Trainer")
      training = create(:training, name_en: "Laser 101")
      event = create(:event, :training, space: space, title: "Training", training: training,
                                        language: "EN")
      create(:event_assignment, event: event, user: staff)
      expect(entries_for(space.id).first["title"])
        .to eq("Laser 101 (#{event.course_name.name} - EN) for Alex Trainer")
    end
  end

  # ---------------------------------------------------------------- publish / drafts

  describe "publish and delete_drafts failure paths" do
    before { log_in!(admin) }

    it "flashes the failure when a single publish cannot save" do
      event = create(:event, :draft, space: space, event_type: "training")
      patch publish_admin_event_path(event)
      expect(flash[:alert]).to eq("Failed to publish event: Training This field is required.")
      expect(event.reload.draft).to be(true)
    end

    # WART(D-B46): Time.parse(nil) raises before the space guard
    it "answers 500 for a batch publish without view dates" do
      patch publish_admin_events_path, params: { space_id: space.id }
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("TypeError")
    end

    # WART(D-B46)
    it "answers 500 for delete_drafts without view dates" do
      delete delete_drafts_admin_events_path, params: { space_id: space.id }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "delete_drafts alerts on a missing space id" do
      draft = create(:event, :draft, space: space)
      delete delete_drafts_admin_events_path,
             params: { view_start_date: "2000-01-01", view_end_date: "2100-01-01" }
      expect(flash[:alert]).to eq("Space ID is required.")
      expect(Event.exists?(draft.id)).to be(true)
    end
  end

  # ---------------------------------------------------------------- copy

  describe "POST copy" do
    before { log_in!(admin) }

    it "copies published non-recurring events (and their assignments) as drafts, skipping drafts and recurring ones" do
      staff = create(:user, :staff)
      source = create(:event, space: space, title: "Source", description: "Orig",
                              start_time: Time.utc(2027, 4, 5, 14, 0), end_time: Time.utc(2027, 4, 5, 15, 30))
      create(:event_assignment, event: source, user: staff)
      create(:event, :draft, space: space, title: "SkippedDraft",
                             start_time: Time.utc(2027, 4, 6, 14, 0), end_time: Time.utc(2027, 4, 6, 15, 0))
      create(:event, :recurring, space: space, title: "SkippedRecurring",
                                 start_time: Time.utc(2027, 4, 7, 14, 0), end_time: Time.utc(2027, 4, 7, 15, 0))
      outside = create(:event, space: space, title: "Outside",
                               start_time: Time.utc(2027, 4, 20, 14, 0), end_time: Time.utc(2027, 4, 20, 15, 0))

      expect do
        post copy_admin_events_path,
             params: { space_id: space.id, source_range: "2027-04-05 to 2027-04-11", target_date: "2027-05-03" }
      end.to change(Event, :count).by(1)

      expect(flash[:notice])
        .to eq("1 published event(s) copied to 2027-05-03. Recurring events were skipped.")
      copy = Event.where(title: "Source").where.not(id: source.id).first
      expect(copy.draft).to be(true)
      expect(copy.description).to eq("Orig")
      expect(copy.google_event_id).to eq("")
      expect(copy.event_assignments.pluck(:user_id)).to eq([staff.id])
      # target date (Eastern midnight) + the original offset into the Eastern day:
      # 14:00 UTC on Apr 5 is 10:00 EDT, so the copy is 10:00 EDT on May 3
      expect(copy.start_time).to eq(Time.utc(2027, 5, 3, 14, 0))
      expect(copy.end_time).to eq(Time.utc(2027, 5, 3, 15, 30))
      expect(Event.where(title: %w[SkippedDraft SkippedRecurring Outside]).count).to eq(3)
      expect(outside.reload.start_time).to eq(Time.utc(2027, 4, 20, 14, 0))
    end

    it "rescues an unparsable range into an error alert" do
      post copy_admin_events_path,
           params: { space_id: space.id, source_range: "garbage to nonsense", target_date: "2027-05-03" }
      expect(flash[:alert]).to start_with("Error copying events: ")
    end
  end
end
