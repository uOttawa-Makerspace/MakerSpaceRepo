# frozen_string_literal: true

require "rails_helper"

# A calendar dialog is a Turbo form: it asks for a Turbo Stream and gets the flash plus the signal that closes the
# dialog and fetches the calendar again. Any other request is redirected as before.
RSpec.describe "Calendar dialog answers", type: :request do
  include SpacesSpecHelpers

  let(:space) { create(:space) }
  let(:admin) { create(:user, :admin, booking_approval: true) }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" } }
  let(:from_calendar) { turbo.merge("HTTP_REFERER" => admin_calendar_index_url) }
  let(:event_params) do
    { event: { event_type: "meeting", title: "Meeting", space_id: space.id,
               utc_start_time: "2027-04-01 10:00", utc_end_time: "2027-04-01 11:00" } }
  end
  let(:series) do
    create(:event, space: space, created_by: admin, start_time: Time.utc(2027, 4, 5, 14), end_time: Time.utc(2027, 4, 5, 15),
                   recurrence_rule: "DTSTART:20270405T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4")
  end

  before do
    admin
    post login_authentication_path, params: { username_email: admin.username, password: "asa32A353#" }
  end

  def expect_stream(text)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('<turbo-stream action="update" target="flash">').and include(text)
    expect(response.body).to include('<turbo-stream action="calendar_saved">')
  end

  describe "admin event dialog" do
    it "answers a create with the stream" do
      expect { post admin_events_path, params: event_params, headers: turbo }.to change(Event, :count).by(1)
      expect_stream("Event created successfully.")
    end

    it "does not show the flash again on the next page" do
      post admin_events_path, params: event_params, headers: turbo
      get admin_calendar_index_path
      expect(response.body).not_to include("Event created successfully.")
    end

    it "answers a refused create with the alert in the stream and saves nothing" do
      expect { post admin_events_path, params: event_params.deep_merge(event: { space_id: nil }), headers: turbo }
        .not_to change(Event, :count)
      expect_stream("Failed to create event")
    end

    it "answers an update with the stream" do
      event = create(:event, space: space, title: "Old", created_by: admin)
      patch admin_event_path(event), params: event_params, headers: turbo
      expect_stream("Event updated successfully.")
      expect(event.reload.title).to eq("Meeting")
    end

    it "answers an update of one occurrence and of the series with the stream" do
      patch admin_event_path(series), params: event_params.merge(update_scope: "nonsense"), headers: turbo
      expect_stream("Invalid update scope.")
      patch admin_event_path(series), params: event_params.merge(update_scope: "this"), headers: turbo
      expect_stream("This event occurrence updated successfully.")
      patch admin_event_path(series), params: event_params.merge(update_scope: "all"), headers: turbo
      expect_stream("Event updated successfully.")
    end

    it "answers a request without usable times with the alert in the stream" do
      patch admin_event_path(series), params: { event: { title: "x", event_type: "meeting" } }, headers: turbo
      expect_stream(I18n.t("admin_events.times_required"))
    end

    it "answers every delete scope with the stream" do
      delete delete_with_scope_admin_event_path(series), params: { scope: "single", start_date: "2027-04-12T14:00:00Z" }, headers: turbo
      expect_stream("This occurrence deleted.")
      delete delete_with_scope_admin_event_path(series), params: { scope: "following", start_date: "2027-04-19T14:00:00Z" }, headers: turbo
      expect_stream("This and following deleted.")
      delete delete_with_scope_admin_event_path(series), params: { scope: "single" }, headers: turbo
      expect_stream(I18n.t("admin_events.start_date_required"))
      delete delete_with_scope_admin_event_path(series), params: { scope: "other" }, headers: turbo
      expect_stream("Invalid delete scope: other")
      delete delete_with_scope_admin_event_path(series), params: { scope: "all" }, headers: turbo
      expect_stream("Event series deleted.")
      expect(Event.exists?(series.id)).to be(false)
    end

    it "answers the delete of a single event with the stream" do
      event = create(:event, space: space, created_by: admin)
      delete delete_with_scope_admin_event_path(event), params: { scope: "all" }, headers: turbo
      expect_stream("Event deleted.")
    end

    it "answers publish and unpublish with the stream" do
      event = create(:event, space: space, created_by: admin, draft: true)
      patch publish_admin_event_path(event), headers: turbo
      expect_stream("Event published successfully.")
      delete admin_event_publication_path(event), headers: turbo
      expect_stream("Event unpublished successfully.")
    end

    it "keeps the redirect for a request that does not ask for a stream" do
      post admin_events_path, params: event_params, headers: { "HTTP_REFERER" => admin_calendar_index_url }
      expect(response).to redirect_to(admin_calendar_index_url)
      expect(flash[:notice]).to eq("Event created successfully.")

      delete delete_with_scope_admin_event_path(series), params: { scope: "all" }
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(flash[:notice]).to eq("Event series deleted.")
    end

    it "keeps the bulk publish as a redirect" do
      patch publish_admin_events_path, params: { space_id: space.id, view_start_date: "2027-04-01", view_end_date: "2027-04-30" },
                                       headers: from_calendar
      expect(response).to redirect_to(admin_calendar_index_url)
    end
  end

  describe "unavailability dialog" do
    let(:attrs) do
      { staff_unavailability: { title: "Class", utc_start_time: "2027-03-01T15:00:00Z", utc_end_time: "2027-03-01T16:00:00Z" } }
    end
    let!(:record) { create(:staff_unavailability, user: admin) }

    it "answers a create, update and delete with the stream" do
      expect { post staff_unavailabilities_path, params: attrs, headers: from_calendar }.to change(StaffUnavailability, :count).by(1)
      expect_stream("Unavailability created.")
      patch staff_unavailability_path(record), params: attrs, headers: from_calendar
      expect_stream("Unavailability updated successfully.")
      delete staff_unavailability_path(record), headers: from_calendar
      expect_stream("Unavailability deleted.")
    end

    it "answers a scoped delete with the stream" do
      delete delete_with_scope_staff_unavailability_path(record), params: { scope: "all" }, headers: turbo
      expect_stream("Unavailability deleted.")
    end

    it "keeps the redirect for a request that does not ask for a stream" do
      post staff_unavailabilities_path, params: attrs, headers: { "HTTP_REFERER" => admin_calendar_index_url }
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(flash[:notice]).to eq("Unavailability created.")
    end
  end
end
