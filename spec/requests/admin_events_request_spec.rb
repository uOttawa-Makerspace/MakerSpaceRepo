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
                           created_by: admin)
    log_in!(admin)
    get json_admin_events_path(id: space.id)
    expect(response.status).to eq(200)

    body = response.parsed_body
    expect(body).to contain_exactly(
      "id" => "meeting",
      "events" => contain_exactly(
        "id" => "event-#{event.id}",
        "title" => "Board",
        "start" => event.start_time.iso8601,
        "end" => event.end_time.iso8601,
        "allDay" => false,
        "extendedProps" => hash_including(
          "draft" => false,
          "eventType" => "meeting",
          "name" => "Meeting"
        )
      )
    )
  end

  it "json drafts surface their draft state + extendedProps skills" do
    event = create(:event, :draft, :recurring, space: space, title: "Draft",
                                               created_by: admin)
    log_in!(admin)
    get json_admin_events_path(id: space.id)
    entry = response.parsed_body.first["events"].first
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

  it "batch publish over a view range + scoped count + space guard" do
    drafts = 2.times.map { create(:event, :draft, space: space) }
    create(:event, space: space) # published earlier, not counted

    log_in!(admin)

    # WART: the no-:id publish branch parses view_start_date/view_end_date
    # BEFORE the space guard — date params must be present or the request
    # 500s before the "Space ID is required." flash can even fire.
    patch publish_admin_events_path, params: {
      view_start_date: Time.zone.yesterday.strftime("%Y-%m-%d"),
      view_end_date: Time.zone.tomorrow.strftime("%Y-%m-%d")
    }
    expect(response).to redirect_to(admin_calendar_index_path)
    expect(flash[:alert]).to eq("Space ID is required.")

    patch publish_admin_events_path, params: {
      space_id: space.id,
      view_start_date: Time.zone.yesterday.strftime("%Y-%m-%d"),
      view_end_date: Time.zone.tomorrow.strftime("%Y-%m-%d")
    }
    expect(flash[:notice]).to eq("2 event(s) published.")
    expect(drafts.map { |e| e.reload.draft }).to all(be(false))
  end

  it "delete_drafts only removes non-recurring drafts" do
    draft = create(:event, :draft, space: space)
    recurring_draft = create(:event, :draft, :recurring, space: space,
                                                         title: "DraftRec")
    published = create(:event, space: space)

    log_in!(admin)
    delete delete_drafts_admin_events_path, params: {
      space_id: space.id,
      view_start_date: Time.zone.yesterday.strftime("%Y-%m-%d"),
      view_end_date: Time.zone.tomorrow.strftime("%Y-%m-%d")
    }
    expect(flash[:notice])
      .to eq("1 draft event(s) deleted. Any recurring events were untouched and must be deleted separately.")
    expect(Event.find_by(id: draft.id)).to be_nil
    expect(Event.find_by(id: recurring_draft.id)).to be_present
    expect(Event.find_by(id: published.id)).to be_present
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
    expect(event.reload.title).to eq("Updated title")
    expect(event.reload.description).to eq("New description")
  end

  it "delete_with_scope: non-recurring event simply destroyed" do
    event = create(:event, space: space)
    log_in!(admin)
    delete delete_with_scope_admin_event_path(event)
    expect(flash[:notice]).to eq("Event deleted.")
    expect(Event.find_by(id: event.id)).to be_nil
  end

  it "delete_with_scope: copies copy invalid (unfilled) fields flash error" do
    log_in!(admin)
    post copy_admin_events_path, params: { space_id: space.id }
    expect(flash[:alert]).to eq("Please fill out all fields before copying.")
  end

  it "delete_with_scope: deletes recurring events who have no start" do
    recurring = create(:event, :recurring, space: space)
    log_in!(admin)
    delete delete_with_scope_admin_event_path(recurring), params: { scope: "single" }
    expect(flash[:alert]).to eq("Start date is required.")
    expect(Event.find_by(id: recurring.id)).to be_present
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
