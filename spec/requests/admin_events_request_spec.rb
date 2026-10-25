# frozen_string_literal: true

require "rails_helper"

# Minimal HTTP contract spec for Admin::EventsController (admin-area).
# Focus: request routing, the UNREACHABLE "Space ID is required" guard on
# json (route requires :id — pinned with id: 0 instead), publish /
# delete flows under admin auth. Non-admin POST/PATCH/DELETE
# activities are redirects to / by AdminAreaController#ensure_admin.

RSpec.describe "Admin events contract", type: :request do
  let(:space) { create(:space) }
  let(:admin) { create(:user, :admin, booking_approval: true) }

  def log_in!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  # NOTE: the controller's `params[:id].blank? → 400` guard on `json` is
  # UNREACHABLE through the real routes: the line is `get 'json/:id'`, so
  # :id is a required segment and omitting it fails at path-helper level.
  # Pinned with an unknown space id (0) instead → 200 + empty payload.
  it "admin json for an unknown space id → 200 with an empty payload" do
    log_in!(admin)
    get json_admin_events_path(id: 0)
    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq([])
  end

  it "json groups events under event_type with ids event-<id>" do
    event = create(:event, space: space, title: "Board", event_type: "meeting",
                           created_by: admin,
                           start_time: Time.utc(2027, 4, 1, 14, 0),
                           end_time: Time.utc(2027, 4, 1, 15, 0))
    log_in!(admin)
    get json_admin_events_path(id: space.id)
    expect(response.status).to eq(200)

    body = response.parsed_body
    expect(body).to contain_exactly(
      "id" => "meeting",
      "events" => contain_exactly(
        "id" => "event-#{event.id}",
        "title" => "Board",
        "start" => "2027-04-01T10:00:00-04:00",
        "end" => "2027-04-01T11:00:00-04:00",
        "allDay" => false,
        "extendedProps" => hash_including(
          "draft" => false,
          "eventType" => "meeting",
          "name" => "Meeting"
        )
      )
    )
  end

  it "json drafts surface their draft state, rrule and the (Draft) title marker" do
    create(:event, :draft, :recurring, space: space, title: "Draft",
                                       created_by: admin)
    log_in!(admin)
    get json_admin_events_path(id: space.id)
    entry = response.parsed_body.first["events"].first
    expect(entry["title"]).to eq("✎ Draft")
    expect(entry["extendedProps"]["draft"]).to be(true)
    expect(entry).to include("rrule")
    expect(entry["allDay"]).to be(false)
  end

  it "single publish PATCH marks draft published" do
    event = create(:event, :draft, space: space)
    log_in!(admin)
    patch publish_admin_event_path(event)
    expect(response).to redirect_to(admin_calendar_index_path)
    expect(flash[:notice]).to eq("Event published successfully.")
    expect(event.reload.draft).to be(false)
  end

  # The view range is built from literal dates and the clock is pinned to the
  # Eastern evening (18:00 EDT = 22:00 UTC on 2027-04-01), the slot where the
  # factory's `Time.zone.now` and the controller's UTC `Time.parse` of the
  # range used to disagree about which calendar day the draft is on.
  it "batch publish over a view range + scoped count + space guard" do
    travel_to(Time.zone.local(2027, 4, 1, 18, 0)) do
      drafts = 2.times.map { create(:event, :draft, space: space) }
      create(:event, space: space) # published earlier, not counted

      log_in!(admin)

      # WART(D-B46): the no-:id publish branch parses view_start_date/
      # view_end_date BEFORE the space guard — date params must be present or
      # the request 500s before the "Space ID is required." flash can even
      # fire (pinned in admin_events_gaps_request_spec.rb).
      patch publish_admin_events_path, params: {
        view_start_date: "2027-03-31", view_end_date: "2027-04-02"
      }
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(flash[:alert]).to eq("Space ID is required.")

      patch publish_admin_events_path, params: {
        space_id: space.id,
        view_start_date: "2027-03-31", view_end_date: "2027-04-02"
      }
      expect(flash[:notice]).to eq("2 event(s) published.")
      expect(drafts.map { |e| e.reload.draft }).to all(be(false))
    end
  end

  it "delete_drafts only removes non-recurring drafts" do
    travel_to(Time.zone.local(2027, 4, 1, 18, 0)) do
      draft = create(:event, :draft, space: space)
      recurring_draft = create(:event, :draft, :recurring, space: space,
                                                           title: "DraftRec")
      published = create(:event, space: space)

      log_in!(admin)
      delete delete_drafts_admin_events_path, params: {
        space_id: space.id,
        view_start_date: "2027-03-31", view_end_date: "2027-04-02"
      }
      expect(flash[:notice])
        .to eq("1 draft event(s) deleted. Any recurring events were untouched and must be deleted separately.")
      expect(Event.find_by(id: draft.id)).to be_nil
      expect(Event.exists?(recurring_draft.id)).to be(true)
      expect(Event.exists?(published.id)).to be(true)
    end
  end

  it "create POST: blank titles fall back to the capitalized event_type" do
    log_in!(admin)
    # space_id is required at the model level; without it the flash never
    # gets its notice (record fails validation on purpose) — so pin with it
    post admin_events_path, params: {
      event: { event_type: "meeting", description: "In-person",
               space_id: space.id,
               utc_start_time: "2027-04-01 10:00",
               utc_end_time: "2027-04-01 11:00" }
    }
    expect(flash[:notice]).to eq("Event created successfully.")
    created = Event.order(:id).last
    expect(created.title).to eq("Meeting")
    expect(created.draft).to be(true) # kept as a draft on this path
    expect(created.event_type).to eq("meeting")
    expect(created.created_by_id).to eq(admin.id)
    expect(created.space_id).to eq(space.id)
    expect(created.description).to eq("In-person")
    expect(created.start_time).to eq(Time.utc(2027, 4, 1, 10, 0))
    expect(created.end_time).to eq(Time.utc(2027, 4, 1, 11, 0))
  end

  it "update PATCH (non-recurring) with a title" do
    event = create(:event, space: space, title: "Update-me",
                           created_by: admin)
    log_in!(admin)
    # space_id must ride along: leaving it blank fails validation and the
    # notice flash is never set
    patch admin_event_path(event), params: {
      event: { event_type: "meeting", title: "Updated title",
               description: "New description",
               space_id: space.id,
               utc_start_time: "2027-04-01 10:00",
               utc_end_time: "2027-04-01 11:00" }
    }
    expect(flash[:notice]).to eq("Event updated successfully.")
    event.reload
    expect(event.title).to eq("Updated title")
    expect(event.description).to eq("New description")
    expect(event.start_time).to eq(Time.utc(2027, 4, 1, 10, 0))
    expect(event.end_time).to eq(Time.utc(2027, 4, 1, 11, 0))
    # WART(D-B43): a non-recurring update overwrites created_by_id with the editor
    expect(event.created_by_id).to eq(admin.id)
  end

  it "delete_with_scope: non-recurring event simply destroyed" do
    event = create(:event, space: space)
    log_in!(admin)
    delete delete_with_scope_admin_event_path(event)
    expect(flash[:notice]).to eq("Event deleted.")
    expect(Event.find_by(id: event.id)).to be_nil
  end

  it "copy: blank source range / target date flashes the fill-out-all-fields alert" do
    log_in!(admin)
    post copy_admin_events_path, params: { space_id: space.id }
    expect(flash[:alert]).to eq("Please fill out all fields before copying.")
  end

  it "delete_with_scope single: a recurring event without a start_date is NOT deleted and flashes an alert" do
    recurring = create(:event, :recurring, space: space)
    log_in!(admin)
    delete delete_with_scope_admin_event_path(recurring), params: { scope: "single" }
    expect(flash[:alert]).to eq("Start date is required.")
    expect(Event.exists?(recurring.id)).to be(true)
  end

  it "delete_with_scope: unknown scope flashes error" do
    recurring = create(:event, :recurring, space: space)
    log_in!(admin)
    delete delete_with_scope_admin_event_path(recurring), params: { scope: "bogus" }
    expect(flash[:alert]).to eq("Invalid delete scope: bogus")
  end

  it "delete_with_scope: all scope nukes the series" do
    recurring = create(:event, :recurring, space: space)
    log_in!(admin)
    delete delete_with_scope_admin_event_path(recurring), params: { scope: "all" }
    expect(flash[:notice]).to eq("Event series deleted.")
    expect(Event.find_by(id: recurring.id)).to be_nil
  end
end
